//
//  ContentView.swift
//  SSHClaude Watch App Watch App
//
//  Created by Kuniqiu on 2026/5/25.
//

import SwiftUI

// Watch 入口已移至 HostListWatchView，此文件保留以免工程引用报错。
struct ContentView: View {
    var body: some View {
        HostListWatchView()
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchClient.shared)
}
