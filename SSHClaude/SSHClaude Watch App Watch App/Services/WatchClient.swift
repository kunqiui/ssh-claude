import Foundation
import Combine
import WatchConnectivity

/// Watch 端的通信客户端。向 iPhone 发消息，维护本地 pane 状态。
///
/// 注意：WCSessionDelegate 回调由系统在后台线程派发，所以这个类不能整体标
/// @MainActor（会导致 delegate 方法签名不匹配，且 SwiftUI 会在后台线程改
/// @Published 触发崩溃警告）。所有写 @Published 的地方必须显式切到主线程。
public class WatchClient: NSObject, ObservableObject, WCSessionDelegate {
    public static let shared = WatchClient()
    private override init() { super.init() }

    @Published public var hosts: [HostInfo] = []
    @Published public var sessions: [TmuxSession] = []
    @Published public var pane: PaneUpdate?
    @Published public var isReachable = false
    @Published public var errorMessage: String?

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // 启动时如果已有缓存的 applicationContext，直接读
        if let data = WCSession.default.receivedApplicationContext["hosts"] as? Data,
           let list = try? WatchCodec.decode([HostInfo].self, from: data) {
            DispatchQueue.main.async { self.hosts = list }
        }
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession,
                        activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {
        let reachable = session.isReachable
        let ctx = session.receivedApplicationContext
        DispatchQueue.main.async {
            self.isReachable = reachable
            if let data = ctx["hosts"] as? Data,
               let list = try? WatchCodec.decode([HostInfo].self, from: data) {
                self.hosts = list
            }
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.isReachable = reachable }
    }

    /// iPhone 通过 updateApplicationContext 推过来的 hosts
    public func session(_ session: WCSession,
                        didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["hosts"] as? Data,
           let list = try? WatchCodec.decode([HostInfo].self, from: data) {
            DispatchQueue.main.async { self.hosts = list }
        }
    }

    // iPhone 主动推送 pane 更新
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let env = WatchEnvelope.from(message) else { return }
        if env.kind == .paneUpdate, let data = env.payload,
           let update = try? WatchCodec.decode(PaneUpdate.self, from: data) {
            DispatchQueue.main.async { self.pane = update }
        }
    }

    // MARK: - 发消息给 iPhone

    @MainActor
    public func fetchHosts() async {
        let env = WatchEnvelope(kind: .listHosts)
        guard let reply = await send(env) else { return }
        if reply.kind == .hostsResult, let data = reply.payload,
           let list = try? WatchCodec.decode([HostInfo].self, from: data) {
            hosts = list
        }
    }

    @MainActor
    public func listSessions(hostId: UUID, sessionName: String = "") async {
        let req = AttachRequest(hostId: hostId, sessionName: sessionName)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .listSessions, payload: data)
        guard let reply = await send(env) else { return }
        if reply.kind == .sessionsResult, let d = reply.payload,
           let list = try? WatchCodec.decode([TmuxSession].self, from: d) {
            sessions = list
        }
    }

    @MainActor
    public func attach(hostId: UUID, sessionName: String) async {
        let req = AttachRequest(hostId: hostId, sessionName: sessionName)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .attachSession, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    @MainActor
    public func refresh(hostId: UUID, sessionName: String) async {
        let req = AttachRequest(hostId: hostId, sessionName: sessionName)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .requestPane, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    @MainActor
    public func sendInput(hostId: UUID, sessionName: String, text: String, submit: Bool) async {
        let req = SendInputRequest(hostId: hostId, sessionName: sessionName, text: text, submit: submit)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .sendInput, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    @MainActor
    public func sendKey(hostId: UUID, sessionName: String, key: SpecialKey) async {
        let req = SendKeyRequest(hostId: hostId, sessionName: sessionName, key: key)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .sendKey, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    /// 让 iPhone 端开始轮询当前会话，"working → idle" 转移时发本地通知。
    @MainActor
    public func startMonitor(hostId: UUID, sessionName: String) async {
        let req = AttachRequest(hostId: hostId, sessionName: sessionName)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .startMonitor, payload: data)
        _ = await send(env)
    }

    @MainActor
    public func stopMonitor() async {
        let env = WatchEnvelope(kind: .stopMonitor)
        _ = await send(env)
    }

    // MARK: - Helpers

    @MainActor
    private func send(_ env: WatchEnvelope) async -> WatchEnvelope? {
        // iPhone 可能被系统清理。sendMessage 需要 reachable，
        // 但 iOS 唤起后台 iPhone 需要 1-2 秒；这里短轮询等它起来。
        if !WCSession.default.isReachable {
            await waitForReachable(timeout: 4.0)
        }
        guard WCSession.default.isReachable else {
            errorMessage = "iPhone 不可达，请打开 iPhone 上的 SSHClaude"
            return nil
        }
        return await withCheckedContinuation { cont in
            WCSession.default.sendMessage(env.toDictionary(), replyHandler: { reply in
                cont.resume(returning: WatchEnvelope.from(reply))
            }, errorHandler: { err in
                DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                cont.resume(returning: nil)
            })
        }
    }

    /// 短轮询等 iPhone 变 reachable。iOS 对后台 iPhone App 的唤起是异步的。
    private func waitForReachable(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if WCSession.default.isReachable { return }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
    }

    @MainActor
    private func handlePaneReply(_ reply: WatchEnvelope) {
        if reply.kind == .paneUpdate, let data = reply.payload,
           let update = try? WatchCodec.decode(PaneUpdate.self, from: data) {
            pane = update
        } else if reply.kind == .error, let data = reply.payload,
                  let err = try? WatchCodec.decode(ErrorPayload.self, from: data) {
            errorMessage = err.message
        }
    }
}
