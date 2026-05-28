import SwiftUI

/// 远端目录浏览器：用于新建会话前选择 cwd。
/// 一次列一层目录，支持上一级、在当前目录新建。
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
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    } header: {
                        Text("子目录")
                    } footer: {
                        Text("点开进入；点右上角“在此新建”在当前目录下创建会话。")
                    }
                } else if !loading && !currentPath.isEmpty {
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
            .safeAreaInset(edge: .top, spacing: 0) { pathBar }
            .overlay {
                if loading && entries.isEmpty {
                    ProgressView().controlSize(.large)
                }
            }
            .toolbar { toolbarContent }
            .task { await load("") }
        }
    }

    // MARK: - Sub-views

    private func entryRow(_ entry: DirEntry) -> some View {
        Button {
            Task { await load(entry.fullPath) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                Text(entry.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
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
        .overlay(alignment: .bottom) { Divider() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - Actions

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
