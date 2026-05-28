import SwiftUI

/// 顶层主机列表。每条 row 进入 [HostSessionsView]。
struct HostListView: View {
    @EnvironmentObject var cm: ConnectionManager
    @State private var showAddHost = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("服务器")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddHost = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加服务器")
                    }
                }
                .sheet(isPresented: $showAddHost) { AddHostView() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if cm.hosts.isEmpty {
            emptyState
        } else {
            hostsList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有服务器", systemImage: "server.rack")
        } description: {
            Text("点右上角加号添加你的第一台 SSH 主机。")
        } actions: {
            Button {
                showAddHost = true
            } label: {
                Text("添加服务器")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var hostsList: some View {
        List {
            ForEach(cm.hosts) { host in
                NavigationLink(destination: HostSessionsView(host: host)) {
                    HostRow(host: host,
                            connected: cm.activeConnections.contains(host.id))
                }
            }
            .onDelete { idx in
                idx.forEach { cm.removeHost(cm.hosts[$0]) }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct HostRow: View {
    let host: HostInfo
    let connected: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatar
            info
            Spacer(minLength: 4)
            statusDot
        }
        .padding(.vertical, 2)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(host.name.prefix(1).uppercased())
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 36, height: 36)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.name).font(.body)
            Text("\(host.username)@\(host.host)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(connected ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 8, height: 8)
    }
}
