import Foundation
import UserNotifications

/// 在 iPhone 端轮询 tmux pane，检测 Claude 任务的"思考 → 就绪"转变。
/// 触发条件后发本地通知；用户手机上可见，配对的 Apple Watch 自动镜像震动。
///
/// 设计要点：
/// - 只在 iPhone App 前台/最近的后台时跑（iOS 后台只给我们几十秒）。
/// - 同一时刻只监测一个 (host, session)；Watch 切到不同会话时旧的会被替换。
/// - 状态机 idle → working → idle，仅在第二次 idle 转移时通知，避免误报。
@MainActor
public final class MonitorService {
    public static let shared = MonitorService()
    private init() {}

    private let cm = ConnectionManager.shared
    private var task: Task<Void, Never>?
    private var watching: Watch?

    /// 当前轮询间隔；Claude 任务通常几十秒到几分钟，5 秒足够。
    private let interval: Duration = .seconds(5)

    private struct Watch {
        let hostId: UUID
        let sessionName: String
        var lastState: SessionState = .unknown
        /// 防止任务刚启动 pane 还是空 / "Welcome back" 这类被误判为 idle。
        /// 必须先看到一次 working，才会在下一次 idle 上触发通知。
        var hasSeenWorking: Bool = false
    }

    /// 开始监测一个会话。重复调用会替换正在监测的目标。
    public func start(hostId: UUID, sessionName: String) {
        // 已经在监测同一目标 → 不打断
        if let w = watching, w.hostId == hostId, w.sessionName == sessionName {
            return
        }
        stop()
        watching = Watch(hostId: hostId, sessionName: sessionName)
        task = Task { [weak self] in await self?.loop() }
    }

    public func stop() {
        task?.cancel()
        task = nil
        watching = nil
    }

    // MARK: - 主循环

    private func loop() async {
        while !Task.isCancelled {
            guard let w = watching else { return }
            await tick(for: w)
            try? await Task.sleep(for: interval)
        }
    }

    private func tick(for w: Watch) async {
        do {
            let pane = try await cm.capturePane(hostId: w.hostId, sessionName: w.sessionName)
            let now = SessionState.classify(pane)
            let prev = w.lastState
            var updated = w
            updated.lastState = now
            if now == .working { updated.hasSeenWorking = true }
            // working → idle 且之前确实见过 working → 通知
            if prev == .working && now == .idle && w.hasSeenWorking {
                Notifier.shared.notifyDone(sessionName: w.sessionName)
            }
            watching = updated
        } catch {
            // 单次失败不致命，继续下一轮
        }
    }
}

// MARK: - 状态判定

enum SessionState: Equatable {
    case unknown
    /// 输入框就绪，等用户输入下一句
    case idle
    /// Claude 在思考或工具执行中
    case working
}

extension SessionState {
    /// 从 capture-pane 文本判断当前状态。判据：
    /// - 含思考动画前缀（· ✢ ✳ ✶ ✻ ✽）→ working
    /// - 末几行没有思考前缀，且能看到 ❯/> 输入提示 → idle
    static func classify(_ pane: String) -> SessionState {
        let lines = pane.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return .unknown }

        let thinkingChars: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽"]
        // 看最近 12 行；思考动画通常是当前/上一行
        let tail = lines.suffix(12)
        let hasThinking = tail.contains { line in
            guard let first = line.first else { return false }
            return thinkingChars.contains(first)
        }
        if hasThinking { return .working }

        let hasPrompt = tail.contains { line in
            line.hasPrefix("❯") || line.hasPrefix(">")
        }
        return hasPrompt ? .idle : .unknown
    }
}

// MARK: - 通知

@MainActor
final class Notifier {
    static let shared = Notifier()
    private init() {}

    private var didRequestAuth = false

    func ensureAuthorization() {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyDone(sessionName: String) {
        let content = UNMutableNotificationContent()
        content.title = sessionName
        content.body = "Claude 任务已完成"
        content.sound = .default
        // 立即触发；nil trigger = 直接送达
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
