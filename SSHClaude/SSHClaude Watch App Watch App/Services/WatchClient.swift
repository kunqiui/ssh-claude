import Foundation
import Combine
import WatchConnectivity

/// Watch 端的通信客户端。向 iPhone 发消息，维护本地 pane 状态。
@MainActor
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
            self.hosts = list
        }
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession,
                        activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {
        isReachable = session.isReachable
        // 激活后再读一次 context（有些场景需要）
        let ctx = session.receivedApplicationContext
        Task { @MainActor in
            if let data = ctx["hosts"] as? Data,
               let list = try? WatchCodec.decode([HostInfo].self, from: data) {
                self.hosts = list
            }
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        isReachable = session.isReachable
    }

    /// iPhone 通过 updateApplicationContext 推过来的 hosts
    public func session(_ session: WCSession,
                        didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["hosts"] as? Data,
           let list = try? WatchCodec.decode([HostInfo].self, from: data) {
            Task { @MainActor in self.hosts = list }
        }
    }

    // iPhone 主动推送 pane 更新
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let env = WatchEnvelope.from(message) else { return }
        if env.kind == .paneUpdate, let data = env.payload,
           let update = try? WatchCodec.decode(PaneUpdate.self, from: data) {
            pane = update
        }
    }

    // MARK: - 发消息给 iPhone

    public func fetchHosts() async {
        let env = WatchEnvelope(kind: .listHosts)
        guard let reply = await send(env) else { return }
        if reply.kind == .hostsResult, let data = reply.payload,
           let list = try? WatchCodec.decode([HostInfo].self, from: data) {
            hosts = list
        }
    }

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

    public func attach(hostId: UUID, sessionName: String) async {
        let req = AttachRequest(hostId: hostId, sessionName: sessionName)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .attachSession, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    public func refresh(hostId: UUID, sessionName: String) async {
        let req = AttachRequest(hostId: hostId, sessionName: sessionName)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .requestPane, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    public func sendInput(hostId: UUID, sessionName: String, text: String, submit: Bool) async {
        let req = SendInputRequest(hostId: hostId, sessionName: sessionName, text: text, submit: submit)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .sendInput, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    public func sendKey(hostId: UUID, sessionName: String, key: SpecialKey) async {
        let req = SendKeyRequest(hostId: hostId, sessionName: sessionName, key: key)
        guard let data = try? WatchCodec.encode(req) else { return }
        let env = WatchEnvelope(kind: .sendKey, payload: data)
        guard let reply = await send(env) else { return }
        handlePaneReply(reply)
    }

    // MARK: - Helpers

    private func send(_ env: WatchEnvelope) async -> WatchEnvelope? {
        guard WCSession.default.isReachable else {
            errorMessage = "iPhone 不可达，请确保 iPhone 已解锁且 App 在前台"
            return nil
        }
        return await withCheckedContinuation { cont in
            WCSession.default.sendMessage(env.toDictionary(), replyHandler: { reply in
                cont.resume(returning: WatchEnvelope.from(reply))
            }, errorHandler: { err in
                Task { @MainActor in self.errorMessage = err.localizedDescription }
                cont.resume(returning: nil)
            })
        }
    }

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
