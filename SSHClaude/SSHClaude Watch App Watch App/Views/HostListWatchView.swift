import SwiftUI

struct HostListWatchView: View {
    @EnvironmentObject var client: WatchClient

    var body: some View {
        NavigationStack {
            Group {
                if !client.isReachable {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.slash")
                            .font(.title2)
                        Text("打开 iPhone 上的 SSHClaude")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                } else if client.hosts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                        Text("在 iPhone App 里添加服务器")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    List(client.hosts) { host in
                        NavigationLink(destination: SessionListWatchView(host: host)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(host.name).font(.headline)
                                Text("\(host.username)@\(host.host)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("SSH Claude")
        }
        .task { await client.fetchHosts() }
        .onChange(of: client.isReachable) { _, reachable in
            if reachable {
                Task { await client.fetchHosts() }
            }
        }
    }
}

struct SessionListWatchView: View {
    let host: HostInfo
    @EnvironmentObject var client: WatchClient

    var claudeSessions: [TmuxSession] { client.sessions.filter(\.isClaude) }
    var otherSessions:  [TmuxSession] { client.sessions.filter { !$0.isClaude } }

    var body: some View {
        List {
            if claudeSessions.isEmpty && otherSessions.isEmpty {
                Text("没有会话").foregroundStyle(.secondary)
            }
            if !claudeSessions.isEmpty {
                Section("Claude") {
                    ForEach(claudeSessions) { s in
                        sessionLink(s)
                    }
                }
            }
            if !otherSessions.isEmpty {
                Section("其他") {
                    ForEach(otherSessions) { s in
                        sessionLink(s)
                    }
                }
            }
        }
        .navigationTitle(host.name)
        .task { await client.listSessions(hostId: host.id) }
        .refreshable { await client.listSessions(hostId: host.id) }
    }

    private func sessionLink(_ s: TmuxSession) -> some View {
        NavigationLink(destination: TerminalView(host: host, session: s)) {
            HStack(spacing: 6) {
                Image(systemName: s.isClaude ? "sparkles.rectangle.stack.fill" : "rectangle.stack")
                    .foregroundStyle(s.isClaude ? .purple : .secondary)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.caption).lineLimit(1)
                    Text(s.attached ? "已附着" : "空闲")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
