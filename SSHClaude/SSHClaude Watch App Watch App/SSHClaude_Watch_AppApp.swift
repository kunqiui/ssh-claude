//
//  SSHClaude_Watch_AppApp.swift
//  SSHClaude Watch App Watch App
//
//  Created by Kuniqiu on 2026/5/25.
//

import SwiftUI

@main
struct SSHClaude_Watch_App_Watch_AppApp: App {
    @StateObject private var client = WatchClient.shared

    var body: some Scene {
        WindowGroup {
            HostListWatchView()
                .environmentObject(client)
                .onAppear { client.activate() }
        }
    }
}
