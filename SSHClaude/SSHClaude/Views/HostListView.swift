import SwiftUI

// MARK: - 顶层主机列表

struct HostListView: View {
    @EnvironmentObject var cm: ConnectionManager
    @State private var showAddHost = false

    var body: some View {
        NavigationStack {
            Group {
                if cm.hosts.isEmpty {
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
                } else {
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
            .sheet(isPresented: $showAddHost) {
                AddHostView()
            }
        }
    }
}

private struct HostRow: View {
    let host: HostInfo
    let connected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                Text(host.name.prefix(1).uppercased())
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.body)
                Text("\(host.username)@\(host.host)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 会话列表

struct HostSessionsView: View {
    let host: HostInfo
    @EnvironmentObject var cm: ConnectionManager
    @State private var sessions: [TmuxSession] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showBrowser = false
    @State private var pendingDelete: TmuxSession?

    private var claudeSessions: [TmuxSession] { sessions.filter(\.isClaude) }
    private var otherSessions: [TmuxSession]  { sessions.filter { !$0.isClaude } }

    var body: some View {
        List {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !claudeSessions.isEmpty {
                Section("Claude 会话") {
                    ForEach(claudeSessions) { s in
                        SessionRow(session: s)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = s
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            if !otherSessions.isEmpty {
                Section("其他会话") {
                    ForEach(otherSessions) { s in
                        SessionRow(session: s)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = s
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            if sessions.isEmpty && !loading {
                Section {
                    Text("还没有会话。点右上角加号在指定目录下新建一个 Claude 会话。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading && sessions.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBrowser = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建 Claude 会话")
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showBrowser) {
            DirectoryBrowserView(host: host) { cwd in
                Task { await newClaude(cwd: cwd) }
            }
        }
        .alert("删除会话？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { s in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                let target = s
                pendingDelete = nil
                Task { await deleteSession(target) }
            }
        } message: { s in
            Text("这将关闭 “\(s.name)”，进行中的工作会丢失，且无法恢复。")
        }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        do { sessions = try await cm.listSessions(hostId: host.id) }
        catch { self.error = "\(error)" }
    }

    private func newClaude(cwd: String) async {
        let name = "claude-\(String(UUID().uuidString.prefix(4)).lowercased())"
        do {
            try await cm.createClaudeSession(hostId: host.id, sessionName: name, cwd: cwd)
            await reload()
        } catch {
            self.error = "\(error)"
        }
    }

    private func deleteSession(_ s: TmuxSession) async {
        do {
            try await cm.killSession(hostId: host.id, sessionName: s.name)
            await reload()
        } catch {
            self.error = "\(error)"
        }
    }
}

private struct SessionRow: View {
    let session: TmuxSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.isClaude ? "sparkles" : "rectangle.stack")
                .font(.callout)
                .foregroundStyle(session.isClaude ? Color.purple : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.body)
                    .lineLimit(1)
                Text(session.attached ? "已附着" : "空闲")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if session.windows > 1 {
                Text("\(session.windows)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 添加主机

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
                Section {
                    TextField("名称", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("主机或 IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("服务器")
                }

                Section {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                } header: {
                    Text("登录")
                } footer: {
                    Text("密码保存在 iPhone 钥匙串，不会发送给 Apple Watch。")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - 目录浏览器

struct DirectoryBrowserView: View {
    let host: HostInfo
    let onPick: (String) -> Void

    @EnvironmentObject var cm: ConnectionManager
    @Environment(\.dismiss) var dismiss
    @State private var currentPath: String = ""
    @State private var entries: [DirEntry] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { e in
                            Button {
                                Task { await load(e.fullPath) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 22)
                                    Text(e.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("子目录")
                    } footer: {
                        Text("点开进入；点右上角“在此新建”在当前目录下创建会话。")
                    }
                } else if !loading && currentPath.isEmpty == false {
                    Section {
                        Text("此目录下没有子目录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择目录")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                pathBar
            }
            .overlay {
                if loading && entries.isEmpty {
                    ProgressView().controlSize(.large)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        Task { await load(parent(of: currentPath)) }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(currentPath.isEmpty || currentPath == "/")
                    .accessibilityLabel("上一级")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("在此新建") {
                        let pick = currentPath
                        dismiss()
                        onPick(pick)
                    }
                    .disabled(currentPath.isEmpty)
                }
            }
            .task { await load("") }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(currentPath.isEmpty ? "正在解析…" : currentPath)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func parent(of path: String) -> String {
        guard path != "/" else { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let i = trimmed.lastIndex(of: "/") {
            let parent = String(trimmed[..<i])
            return parent.isEmpty ? "/" : parent
        }
        return "/"
    }

    private func load(_ path: String) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let resolved = try await cm.resolvePath(hostId: host.id, path: path)
            currentPath = resolved.isEmpty ? path : resolved
            entries = try await cm.listDirectories(hostId: host.id, path: currentPath)
        } catch {
            self.error = "\(error)"
        }
    }
}
