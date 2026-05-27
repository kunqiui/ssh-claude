import SwiftUI

@main
struct SSHClaudeApp: App {
    @StateObject private var cm = ConnectionManager.shared
    @StateObject private var bridge = WatchBridge.shared

    init() {
        // 关键：不要放进 .onAppear。iPhone 被 iOS 清理后由 Watch 后台唤起时
        // 没有 UI，.onAppear 不会触发，会导致 Watch 收不到响应（"没有会话"）。
        ConnectionManager.shared.loadHosts()
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environmentObject(cm)
        }
    }
}
