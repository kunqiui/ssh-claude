import SwiftUI

@main
struct SSHClaude_Watch_App_Watch_AppApp: App {
    @StateObject private var client = WatchClient.shared

    init() {
        // 必须在 init 里激活，否则首次发消息会报 "WCSession has not been activated"
        WatchClient.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HostListWatchView()
                .environmentObject(client)
        }
    }
}
