//
//  ContentView.swift
//  SSHClaude
//
//  Created by Kuniqiu on 2026/5/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HostListView()
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionManager.shared)
}
