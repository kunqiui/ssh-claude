import Foundation
import Combine
import WatchConnectivity

/// iPhone 端的 WatchConnectivity 桥。
/// 接收 Watch 发来的指令，调用 ConnectionManager，把结果回传给 Watch。
@MainActor
public class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    public static let shared = WatchBridge()
    private override init() { super.init() }

    private let cm = ConnectionManager.shared

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession,
                        activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {}

    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    public func session(_ session: WCSession,
                        didReceiveMessage message: [String: Any],
                        replyHandler: @escaping ([String: Any]) -> Void) {
        guard let envelope = WatchEnvelope.from(message) else {
            replyHandler(errorReply("无效消息格式"))
            return
        }
        Task { await self.handle(envelope, reply: replyHandler) }
    }

    // MARK: - 消息处理

    private func handle(_ env: WatchEnvelope, reply: @escaping ([String: Any]) -> Void) async {
        do {
            switch env.kind {
            case .listSessions:
                guard let payload = env.payload,
                      let req = try? WatchCodec.decode(AttachRequest.self, from: payload) else {
                    // listSessions 只需要 hostId，复用 AttachRequest 的 hostId 字段
                    // 如果没有 payload，返回所有 host 的会话列表
                    reply(errorReply("缺少 hostId"))
                    return
                }
                let sessions = try await cm.listSessions(hostId: req.hostId)
                let data = try WatchCodec.encode(sessions)
                reply(WatchEnvelope(kind: .sessionsResult, payload: data).toDictionary())

            case .attachSession:
                guard let payload = env.payload,
                      let req = try? WatchCodec.decode(AttachRequest.self, from: payload) else {
                    reply(errorReply("缺少参数")); return
                }
                try await cm.attachSession(hostId: req.hostId, sessionName: req.sessionName)
                let pane = try await cm.capturePane(hostId: req.hostId, sessionName: req.sessionName)
                let update = PaneUpdate(sessionName: req.sessionName, text: pane)
                let data = try WatchCodec.encode(update)
                reply(WatchEnvelope(kind: .paneUpdate, payload: data).toDictionary())

            case .requestPane:
                guard let payload = env.payload,
                      let req = try? WatchCodec.decode(AttachRequest.self, from: payload) else {
                    reply(errorReply("缺少参数")); return
                }
                let pane = try await cm.capturePane(hostId: req.hostId, sessionName: req.sessionName)
                let update = PaneUpdate(sessionName: req.sessionName, text: pane)
                let data = try WatchCodec.encode(update)
                reply(WatchEnvelope(kind: .paneUpdate, payload: data).toDictionary())

            case .sendInput:
                guard let payload = env.payload,
                      let req = try? WatchCodec.decode(SendInputRequest.self, from: payload) else {
                    reply(errorReply("缺少参数")); return
                }
                try await cm.sendInput(hostId: req.hostId, sessionName: req.sessionName,
                                       text: req.text, submit: req.submit)
                // 发完立刻抓一次 pane 回传
                let pane = try await cm.capturePane(hostId: req.hostId, sessionName: req.sessionName)
                let update = PaneUpdate(sessionName: req.sessionName, text: pane)
                let data = try WatchCodec.encode(update)
                reply(WatchEnvelope(kind: .paneUpdate, payload: data).toDictionary())

            case .sendKey:
                guard let payload = env.payload,
                      let req = try? WatchCodec.decode(SendKeyRequest.self, from: payload) else {
                    reply(errorReply("缺少参数")); return
                }
                try await cm.sendKey(hostId: req.hostId, sessionName: req.sessionName, key: req.key)
                let pane = try await cm.capturePane(hostId: req.hostId, sessionName: req.sessionName)
                let update = PaneUpdate(sessionName: req.sessionName, text: pane)
                let data = try WatchCodec.encode(update)
                reply(WatchEnvelope(kind: .paneUpdate, payload: data).toDictionary())

            case .listHosts:
                let hosts = cm.hosts
                let data = try WatchCodec.encode(hosts)
                reply(WatchEnvelope(kind: .hostsResult, payload: data).toDictionary())

            default:
                reply(errorReply("不支持的消息类型: \(env.kind.rawValue)"))
            }
        } catch {
            reply(errorReply(error.localizedDescription))
        }
    }

    // MARK: - Push pane update to Watch (主动推送，无需 Watch 轮询)

    public func pushPaneUpdate(_ update: PaneUpdate) {
        guard WCSession.default.isReachable,
              let data = try? WatchCodec.encode(update) else { return }
        let env = WatchEnvelope(kind: .paneUpdate, payload: data)
        WCSession.default.sendMessage(env.toDictionary(), replyHandler: nil)
    }

    // MARK: - Helpers

    private func errorReply(_ msg: String) -> [String: Any] {
        let payload = try? WatchCodec.encode(ErrorPayload(msg))
        return WatchEnvelope(kind: .error, payload: payload).toDictionary()
    }
}
