import SwiftUI

/// Watch 上的「终端视图」——其实就是只读 pane 文本 + 一组按键 + 一个文本输入入口。
/// 设计取舍：屏幕太小，不做真正的 PTY 渲染；只显示 capture-pane 的纯文本最后 N 行。
struct TerminalView: View {
    let host: HostInfo
    let session: TmuxSession
    @EnvironmentObject var client: WatchClient
    @State private var inputText = ""
    @State private var showInputSheet = false

    private var paneLines: [String] {
        let raw = client.pane?.text ?? "正在加载…"
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                // 过滤纯下划线分隔线（如 "___" "────" 等）
                let stripped = line.replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "─", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "=", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if stripped.isEmpty { return false }
                let lower = line.lowercased()
                // 过滤 tip 提示行（前面可能有 ⎿ ※ 等装饰前缀和空格）
                if lower.contains("tip:") { return false }
                // 过滤底部快捷键提示（如 "? for shortcuts" / "ctrl+c to exit"）
                if lower.contains("for shortcuts") { return false }
                if lower.hasPrefix("?") && lower.contains("shortcut") { return false }
                // 过滤 Claude 思考状态行（前缀池：· ✢ ✳ ✶ ✻ ✽，星星呼吸动画）
                let statusChars: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽"]
                if let first = line.first, statusChars.contains(first) { return false }
                return true
            }
        return lines.suffix(20).map { String($0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(paneLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: client.pane?.timestamp) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .navigationTitle(session.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await client.refresh(hostId: host.id, sessionName: session.name) }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                inputBar
                keyRow
            }
            .padding(.horizontal, 4).padding(.bottom, 2)
        }
        .task { await client.attach(hostId: host.id, sessionName: session.name) }
        .sheet(isPresented: $showInputSheet) {
            DictationInputView(initial: inputText) { text, submit in
                Task {
                    await client.sendInput(hostId: host.id, sessionName: session.name,
                                           text: text, submit: submit)
                }
            }
        }
    }

    private var inputBar: some View {
        Button {
            inputText = ""
            showInputSheet = true
        } label: {
            HStack {
                Image(systemName: "mic.fill")
                Text("说话或输入").lineLimit(1)
                Spacer()
            }
            .font(.caption)
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(Color.purple.opacity(0.25), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var keyRow: some View {
        HStack(spacing: 4) {
            clearBtn
            keyBtn("xmark.octagon.fill", .ctrlC)
            keyBtn("chevron.up", .up)
            keyBtn("chevron.down", .down)
            keyBtn("return", .enter)
        }
    }

    private var clearBtn: some View {
        Button {
            Task {
                await client.sendInput(hostId: host.id, sessionName: session.name,
                                       text: "/clear", submit: true)
            }
        } label: {
            Text("/clear")
                .font(.system(size: 8, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    private func keyBtn(_ icon: String, _ key: SpecialKey) -> some View {
        Button {
            Task { await client.sendKey(hostId: host.id, sessionName: session.name, key: key) }
        } label: {
            Image(systemName: icon).font(.caption)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .buttonStyle(.bordered)
        .tint(key == .ctrlC ? .red : .blue)
    }
}

/// 输入面板：调用 watchOS TextField 自带的听写/Scribble/最近选项。
/// 不需要自己集成 SFSpeechRecognizer。
struct DictationInputView: View {
    let initial: String
    let onSubmit: (String, Bool) -> Void
    @State private var text: String
    @Environment(\.dismiss) var dismiss

    init(initial: String, onSubmit: @escaping (String, Bool) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        self._text = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 6) {
            // 重要：watchOS 的 TextField 会弹系统输入面板（含听写）
            TextField("输入或说话", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
            HStack {
                Button("取消") { dismiss() }.tint(.secondary)
                Button {
                    onSubmit(text, true)
                    dismiss()
                } label: {
                    Label("发送", systemImage: "paperplane.fill")
                }
                .tint(.purple)
                .disabled(text.isEmpty)
            }
            Button("发送但不回车") {
                onSubmit(text, false)
                dismiss()
            }
            .font(.caption2)
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 6)
    }
}
