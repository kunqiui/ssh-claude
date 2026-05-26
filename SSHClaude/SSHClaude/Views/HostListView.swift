import SwiftUI

struct HostListView: View {
    @EnvironmentObject var cm: ConnectionManager
    @State private var showAddHost = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(cm.hosts) { host in
                    NavigationLink(destination: HostSessionsView(host: host)) {
                        HStack {
                            Image(systemName: cm.activeConnections.contains(host.id)
                                  ? "network" : "network.slash")
                                .foregroundStyle(cm.activeConnections.contains(host.id) ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(host.name).font(.headline)
                                Text("\(host.username)@\(host.host):\(host.port)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    idx.forEach { cm.removeHost(cm.hosts[$0]) }
                }
            }
            .navigationTitle("SSH Claude")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddHost = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddHost) {
                AddHostView()
            }
        }
    }
}

struct HostSessionsView: View {
    let host: HostInfo
    @EnvironmentObject var cm: ConnectionManager
    @State private var sessions: [TmuxSession] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if loading { ProgressView() }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Section("Claude 会话") {
                ForEach(sessions.filter(\.isClaude)) { s in
                    sessionRow(s)
                }
                Button("新建 claude 会话") {
                    Task { await newClaude() }
                }
            }
            Section("其他会话") {
                ForEach(sessions.filter { !$0.isClaude }) { s in
                    sessionRow(s)
                }
            }
        }
        .navigationTitle(host.name)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func sessionRow(_ s: TmuxSession) -> some View {
        HStack {
            Image(systemName: s.isClaude ? "sparkles.rectangle.stack.fill" : "rectangle.stack")
                .foregroundStyle(s.isClaude ? .purple : .secondary)
            VStack(alignment: .leading) {
                Text(s.name).font(.headline)
                Text("\(s.windows) 窗口 · \(s.attached ? "已附着" : "空闲")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        do { sessions = try await cm.listSessions(hostId: host.id) }
        catch { self.error = "\(error)" }
    }

    private func newClaude() async {
        let name = "claude-\(String(UUID().uuidString.prefix(4)).lowercased())"
        do {
            try await cm.attachSession(hostId: host.id, sessionName: name)
            await reload()
        } catch {
            self.error = "\(error)"
        }
    }
}

struct AddHostView: View {
    @EnvironmentObject var cm: ConnectionManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器信息") {
                    TextField("名称（如 my-server）", text: $name)
                    TextField("主机 / IP", text: $host)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("端口", text: $port).keyboardType(.numberPad)
                    TextField("用户名", text: $username)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section("认证") {
                    SecureField("密码", text: $password)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("添加服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty || host.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
    }

    private func save() {
        let info = HostInfo(name: name, host: host,
                            port: Int(port) ?? 22,
                            username: username,
                            credentialRef: "keychain")
        do {
            try cm.addHost(info, password: password)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}
