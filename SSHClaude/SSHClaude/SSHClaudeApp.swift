import SwiftUI

@main
struct SSHClaudeApp: App {
    @StateObject private var cm = ConnectionManager.shared
    @StateObject private var bridge = WatchBridge.shared

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environmentObject(cm)
                .onAppear {
                    cm.loadHosts()
                    bridge.activate()
                }
        }
    }
}
