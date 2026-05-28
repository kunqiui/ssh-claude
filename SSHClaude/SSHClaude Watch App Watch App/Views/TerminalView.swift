import SwiftUI

/// Watch 上的「终端视图」——其实就是只读 pane 文本 + 一组按键 + 一个文本输入入口。
/// 设计取舍：屏幕太小，不做真正的 PTY 渲染；只显示 capture-pane 的纯文本最后 N 行。
struct TerminalView: View {
    let host: HostInfo
    let session: TmuxSession
    @EnvironmentObject var client: WatchClient
    @State private var inputText = ""
    @State private var showInputSheet = false
    @State private var showFunctionSheet = false

    private var paneLines: [String] {
        let raw = client.pane?.text ?? "正在加载…"
        return PaneFilter.clean(raw, tailing: 40)
    }

    /// Claude TUI 的输入行：以 ">" 或 "❯" 开头（前面可能有空格）。
    private func isInputLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(">") || trimmed.hasPrefix("❯")
    }

    /// 经典终端配色：
    /// - 输入行（"❯" 或 ">" 开头的 prompt）亮黄色 + 加粗，强对比
    /// - Claude 工具调用结果行（"⎿" 等装饰）半透明绿，弱化
    /// - 其他全是绿油油的输出
    private func color(for line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") || trimmed.hasPrefix("❯") {
            return Color(red: 1.0, green: 0.92, blue: 0.3) // 亮黄
        }
        if trimmed.hasPrefix("⎿") {
            return Color.green.opacity(0.55)
        }
        return Color(red: 0.4, green: 1.0, blue: 0.4) // phosphor green
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(paneLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced)
                                  .weight(isInputLine(line) ? .semibold : .regular))
                            .foregroundStyle(color(for: line))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 4)
            }
            .background(Color.black)
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
            keyRow
                .padding(.horizontal, 4).padding(.bottom, 2)
        }
        .task {
            await client.attach(hostId: host.id, sessionName: session.name)
            // 让 iPhone 端开始轮询，Claude 任务完成时自动通知（通知会镜像到 Watch 震动）
            await client.startMonitor(hostId: host.id, sessionName: session.name)
        }
        .onDisappear {
            // 离开终端视图就停掉 iPhone 端的轮询，避免空跑耗电
            Task { await client.stopMonitor() }
        }
        .sheet(isPresented: $showInputSheet) {
            DictationInputView(initial: inputText) { text in
                Task {
                    await client.sendInput(hostId: host.id, sessionName: session.name,
                                           text: text, submit: true)
                }
            }
        }
        .sheet(isPresented: $showFunctionSheet) {
            FunctionKeysView { action in
                Task {
                    switch action {
                    case .clear:
                        await client.sendInput(hostId: host.id, sessionName: session.name,
                                               text: "/clear", submit: true)
                    case .launchClaude:
                        await client.sendInput(hostId: host.id, sessionName: session.name,
                                               text: "claude --dangerously-skip-permissions", submit: true)
                    case .key(let k):
                        await client.sendKey(hostId: host.id, sessionName: session.name, key: k)
                    }
                }
            }
        }
    }

    private var keyRow: some View {
        HStack(spacing: 4) {
            functionBtn
            micBtn
        }
    }

    private var functionBtn: some View {
        Button {
            showFunctionSheet = true
        } label: {
            Image(systemName: "command")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    private var micBtn: some View {
        Button {
            inputText = ""
            showInputSheet = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(.purple)
    }
}

enum FunctionAction {
    case clear
    case launchClaude
    case key(SpecialKey)
}

/// 功能键面板：把不常用的按键收纳进来，主屏只留麦克风和功能入口。
struct FunctionKeysView: View {
    let onPick: (FunctionAction) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                row(label: "claude", icon: "sparkles", tint: .purple, action: .launchClaude)
                row(label: "/clear", tint: .orange, action: .clear)
                row(label: "Enter", icon: "return", tint: .blue, action: .key(.enter))
                row(label: "Esc", icon: "escape", tint: .red, action: .key(.escape))
                row(label: "Up", icon: "chevron.up", tint: .blue, action: .key(.up))
                row(label: "Down", icon: "chevron.down", tint: .blue, action: .key(.down))
            }
            .padding(.horizontal, 6)
        }
    }

    private func row(label: String, icon: String? = nil, tint: Color, action: FunctionAction) -> some View {
        Button {
            onPick(action)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(label).font(.system(.body, design: .monospaced))
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

/// 输入面板：调用 watchOS TextField 自带的听写/Scribble/最近选项。
/// 不需要自己集成 SFSpeechRecognizer。
struct DictationInputView: View {
    let initial: String
    let onSubmit: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) var dismiss

    init(initial: String, onSubmit: @escaping (String) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        self._text = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("输入或说话", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
            Button {
                onSubmit(text)
                dismiss()
            } label: {
                Label("发送", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.purple)
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 6)
    }
}
