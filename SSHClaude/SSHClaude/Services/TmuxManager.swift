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
    /// cwd 给 tmux new-session -c 用，让会话以指定目录为工作目录。
    @discardableResult
    public func ensureSession(name: String, command: String? = nil, cwd: String? = nil) async throws -> TmuxSession {
        let exists = try await sessionExists(name: name)
        if !exists {
            let escaped = shellEscape(name)
            let cwdFlag: String
            if let cwd, !cwd.isEmpty {
                cwdFlag = " -c \(shellEscape(cwd))"
            } else {
                cwdFlag = ""
            }
            // 先建空 session，让 tmux 用用户登录 shell 启动 pane（PATH 完整）。
            // 再通过 send-keys 注入命令，等同于用户手动在 tmux 里输入。
            // 注意：SSHClient.run 已经把整条命令包在 $SHELL -ilc 里，所以这里
            // 直接写 "tmux ..." 即可，不需要再担心 PATH。
            _ = try await ssh.run("tmux new-session -d -s \(escaped)\(cwdFlag)")
            if let command, !command.isEmpty {
                _ = try await ssh.run("tmux send-keys -t \(escaped) \(shellEscape(command)) Enter")
            }
        }
        let sessions = try await list()
        guard let s = sessions.first(where: { $0.name == name }) else {
            throw TmuxError.sessionMissing(name)
        }
        return s
    }

    /// 列出指定目录下的子目录（一层）。返回 (name, isDir) 列表，按字母排序。
    /// path 为空时使用 $HOME。
    public func listDirectories(path: String) async throws -> [DirEntry] {
        let target: String
        if path.isEmpty {
            target = "$HOME"
        } else {
            target = shellEscape(path)
        }
        // ls -1Ap：每行一项、显示隐藏文件、目录加 /
        // 通过 / 后缀识别目录，过滤掉非目录
        let cmd = "cd \(target) 2>/dev/null && pwd && ls -1Ap 2>/dev/null || true"
        let out = try await ssh.run(cmd)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let absolute = lines.first, !absolute.isEmpty else {
            return []
        }
        let entries = lines.dropFirst().compactMap { line -> DirEntry? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasSuffix("/") {
                let name = String(trimmed.dropLast())
                guard !name.isEmpty else { return nil }
                return DirEntry(name: name, isDirectory: true, parentPath: absolute)
            }
            return nil
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 把 path 解析成绝对路径（处理 ~ 等）。
    public func resolvePath(_ path: String) async throws -> String {
        let target = path.isEmpty ? "$HOME" : shellEscape(path)
        let cmd = "cd \(target) 2>/dev/null && pwd || true"
        return try await ssh.run(cmd).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func sessionExists(name: String) async throws -> Bool {
        let cmd = "tmux has-session -t \(shellEscape(name)) 2>/dev/null && echo Y || echo N"
        let out = try await ssh.run(cmd)
        return out.contains("Y")
    }

    public func capturePane(session: String, lines: Int = 120) async throws -> String {
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

/// 远端目录浏览的一行
public struct DirEntry: Identifiable, Hashable {
    public var id: String { parentPath + "/" + name }
    public let name: String
    public let isDirectory: Bool
    /// 当前 ls 时所在的绝对路径（pwd 输出）
    public let parentPath: String
    public var fullPath: String {
        if parentPath.hasSuffix("/") { return parentPath + name }
        return parentPath + "/" + name
    }
}

nonisolated func shellEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
