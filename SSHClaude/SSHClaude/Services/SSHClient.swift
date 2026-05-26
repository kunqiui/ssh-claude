import Foundation
import NIOCore

/// 轻量 SSH 客户端包装。底层用 Citadel（基于 SwiftNIO SSH）。
/// 每个 HostInfo 对应一个 SSHClient 实例，由 ConnectionManager 持有。
public actor SSHClient {
    private let host: String
    private let port: Int
    private let username: String
    private let password: String

    // Citadel 的 SSHClient 类型，装包后引用
    private var inner: CitadelSSHClient?

    public init(host: String, port: Int, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    public func connect() async throws {
        let client = try await CitadelSSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: .passwordBased(username: username, password: password),
            hostKeyValidator: .acceptAnything(), // 生产环境应改为 known_hosts 校验
            reconnect: .never
        )
        self.inner = client
    }

    public func disconnect() async {
        try? await inner?.close()
        inner = nil
    }

    public var isConnected: Bool { inner != nil }

    /// 执行单条命令，返回 stdout 字符串。
    public func run(_ command: String) async throws -> String {
        guard let client = inner else { throw SSHError.notConnected }
        let bytes = try await client.executeCommand(command)
        return String(buffer: bytes)
    }
}

public enum SSHError: Error, LocalizedError {
    case notConnected
    case authFailed
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:    return "SSH 未连接"
        case .authFailed:      return "SSH 认证失败"
        case .commandFailed(let msg): return "命令失败: \(msg)"
        }
    }
}

// MARK: - Citadel 类型别名（避免全局 import 污染）
// 实际编译时需要 import Citadel，这里用 typealias 隔离
import Citadel
private typealias CitadelSSHClient = Citadel.SSHClient
