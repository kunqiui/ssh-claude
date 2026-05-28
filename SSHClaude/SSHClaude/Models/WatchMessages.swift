import Foundation

/// iPhone 与 Watch 之间通过 WatchConnectivity 交换的消息协议。
/// 使用单一信封 + JSON payload，方便后续扩展。
public enum WatchMessageKind: String, Codable {
    // Watch -> iPhone
    case listSessions
    case attachSession
    case sendInput
    case sendKey
    case requestPane
    case addCredential
    case listHosts
    case connectHost
    case startMonitor
    case stopMonitor

    // iPhone -> Watch
    case sessionsResult
    case paneUpdate
    case ack
    case error
    case hostsResult
    case connected
    case disconnected
}

public struct WatchEnvelope: Codable {
    public let id: UUID
    public let kind: WatchMessageKind
    public let payload: Data?

    public init(id: UUID = UUID(), kind: WatchMessageKind, payload: Data? = nil) {
        self.id = id
        self.kind = kind
        self.payload = payload
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "kind": kind.rawValue
        ]
        if let payload { dict["payload"] = payload }
        return dict
    }

    public static func from(_ dict: [String: Any]) -> WatchEnvelope? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let kindString = dict["kind"] as? String,
              let kind = WatchMessageKind(rawValue: kindString) else {
            return nil
        }
        let payload = dict["payload"] as? Data
        return WatchEnvelope(id: id, kind: kind, payload: payload)
    }
}

// MARK: - Payloads

public struct HostInfo: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    /// Keychain 里凭据的引用键。Watch 拿不到密码，只发指令让 iPhone 用本地凭据连。
    public var credentialRef: String

    public init(id: UUID = UUID(), name: String, host: String, port: Int = 22,
                username: String, credentialRef: String) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.credentialRef = credentialRef
    }
}

public struct TmuxSession: Codable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var windows: Int
    public var attached: Bool
    public var createdAt: Date?
    /// 用于快速识别 Claude 会话的标签，例如名字以 claude- 开头或包含 claude
    public var isClaude: Bool

    public init(name: String, windows: Int, attached: Bool, createdAt: Date?, isClaude: Bool) {
        self.name = name
        self.windows = windows
        self.attached = attached
        self.createdAt = createdAt
        self.isClaude = isClaude
    }
}

public struct AttachRequest: Codable {
    public let hostId: UUID
    public let sessionName: String
    public init(hostId: UUID, sessionName: String) {
        self.hostId = hostId
        self.sessionName = sessionName
    }
}

public struct SendInputRequest: Codable {
    public let hostId: UUID
    public let sessionName: String
    public let text: String
    /// 是否在末尾自动追加 Enter（C-m）。语音输入完成后默认追加。
    public let submit: Bool
    public init(hostId: UUID, sessionName: String, text: String, submit: Bool) {
        self.hostId = hostId
        self.sessionName = sessionName
        self.text = text
        self.submit = submit
    }
}

public enum SpecialKey: String, Codable, CaseIterable {
    case enter
    case escape
    case tab
    case ctrlC
    case up
    case down
    case left
    case right
    case backspace

    /// 翻译为 tmux send-keys 的参数。
    public var tmuxToken: String {
        switch self {
        case .enter:     return "Enter"
        case .escape:    return "Escape"
        case .tab:       return "Tab"
        case .ctrlC:     return "C-c"
        case .up:        return "Up"
        case .down:      return "Down"
        case .left:      return "Left"
        case .right:     return "Right"
        case .backspace: return "BSpace"
        }
    }
}

public struct SendKeyRequest: Codable {
    public let hostId: UUID
    public let sessionName: String
    public let key: SpecialKey
    public init(hostId: UUID, sessionName: String, key: SpecialKey) {
        self.hostId = hostId
        self.sessionName = sessionName
        self.key = key
    }
}

public struct PaneUpdate: Codable {
    public let sessionName: String
    /// 当前可见 pane 的纯文本截图（tmux capture-pane）。
    public let text: String
    public let timestamp: Date
    public init(sessionName: String, text: String, timestamp: Date = Date()) {
        self.sessionName = sessionName
        self.text = text
        self.timestamp = timestamp
    }
}

public struct ErrorPayload: Codable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - 编码助手

public enum WatchCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
