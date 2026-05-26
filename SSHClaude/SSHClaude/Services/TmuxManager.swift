import Foundation

/// 在远端通过 tmux 命令管理会话。所有调用都走 SSHClient.run("tmux ...")。
/// 设计原则：永远不建立"长连 shell"，每个动作都是一次性命令，对 Watch 友好。
public actor TmuxManager {
    private let ssh: SSHClient
    public init(ssh: SSHClient) { self.ssh = ssh }

    /// 列出所有会话。tmux 不存在或没有会话时返回空。
    public func list() async throws -> [TmuxSession] {
        // 自定义格式更稳：name|windows|attached|created
        let cmd = #"tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_created}' 2>/dev/null || true"#
        let out = try await ssh.run(cmd)
        return out
            .split(separator: "\n")
            .compactMap { line -> TmuxSession? in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 4 else { return nil }
                let name = parts[0]
                let windows = Int(parts[1]) ?? 1
                let attached = (parts[2] == "1")
                let createdAt: Date? = Double(parts[3]).map { Date(timeIntervalSince1970: $0) }
                let isClaude = name.lowercased().contains("claude")
                return TmuxSession(name: name, windows: windows,
                                   attached: attached, createdAt: createdAt,
                                   isClaude: isClaude)
            }
    }

    /// 确保有一个名为 sessionName 的会话；没有就新建并启动 claude。
    /// command 为空时只 new-session 不跑命令。
    @discardableResult
    public func ensureSession(name: String, command: String? = nil) async throws -> TmuxSession {
        let exists = try await sessionExists(name: name)
        if !exists {
            let escaped = shellEscape(name)
            if let command, !command.isEmpty {
                // bash -i 加载 ~/.bashrc，确保 PATH 和环境变量（如 ANTHROPIC_API_KEY）可用
                let wrappedCmd = shellEscape("bash -i -c \(shellEscape(command))")
                _ = try await ssh.run("tmux new-session -d -s \(escaped) \(wrappedCmd)")
            } else {
                _ = try await ssh.run("tmux new-session -d -s \(escaped)")
            }
        }
        let sessions = try await list()
        guard let s = sessions.first(where: { $0.name == name }) else {
            throw TmuxError.sessionMissing(name)
        }
        return s
    }

    public func sessionExists(name: String) async throws -> Bool {
        let cmd = "tmux has-session -t \(shellEscape(name)) 2>/dev/null && echo Y || echo N"
        let out = try await ssh.run(cmd)
        return out.contains("Y")
    }

    public func capturePane(session: String, lines: Int = 40) async throws -> String {
        // 去掉 ANSI 转义，每行截到38字符（Watch 屏宽约38字符）
        let cmd = "tmux capture-pane -p -t \(shellEscape(session)) -S -\(lines) 2>/dev/null | sed 's/\\x1b\\[[0-9;]*[mGKHFJA-Z]//g' || true"
        return try await ssh.run(cmd)
    }

    public func sendInput(session: String, text: String, submit: Bool) async throws {
        let cmd = "tmux send-keys -t \(shellEscape(session)) -l \(shellEscape(text))"
        _ = try await ssh.run(cmd)
        if submit {
            _ = try await ssh.run("tmux send-keys -t \(shellEscape(session)) Enter")
        }
    }

    public func sendKey(session: String, key: SpecialKey) async throws {
        let cmd = "tmux send-keys -t \(shellEscape(session)) \(key.tmuxToken)"
        _ = try await ssh.run(cmd)
    }

    public func killSession(name: String) async throws {
        _ = try await ssh.run("tmux kill-session -t \(shellEscape(name))")
    }
}

public enum TmuxError: Error {
    case sessionMissing(String)
}

nonisolated func shellEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
