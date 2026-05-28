import SwiftUI

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
        let name = TmuxSessionNamer.name(for: cwd, existing: sessions.map(\.name))
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

// MARK: - Row

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

// MARK: - 命名规则

/// 根据 cwd 生成 tmux 会话名：claude-{目录名}。
/// 根目录 → claude-root；空路径 → claude-home；
/// 同名已存在则追加数字后缀（claude-foo-2 / -3 ...）。
enum TmuxSessionNamer {
    static func name(for cwd: String, existing: [String]) -> String {
        let base = "claude-\(safeLeaf(of: cwd))"
        guard existing.contains(base) else { return base }
        var i = 2
        while existing.contains("\(base)-\(i)") { i += 1 }
        return "\(base)-\(i)"
    }

    private static func safeLeaf(of cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let leaf: String
        if cwd.isEmpty {
            leaf = "home"
        } else if trimmed.isEmpty {
            leaf = "root"
        } else {
            leaf = trimmed.split(separator: "/").last.map(String.init) ?? "home"
        }
        // tmux 会话名不能含 . : 空格
        return leaf
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
    }
}
