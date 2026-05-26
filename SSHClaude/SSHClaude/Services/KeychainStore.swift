import Foundation
import Security

/// 把 SSH 凭据存进 Keychain，Watch 端永远拿不到密码，只发 hostId 让 iPhone 用本地凭据连。
public enum KeychainStore {
    private static let service = "com.kuniqiu.SSHClaude"

    public static func save(hostId: UUID, password: String) throws {
        let data = Data(password.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: hostId.uuidString,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public static func load(hostId: UUID) throws -> String {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      hostId.uuidString,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        return password
    }

    public static func delete(hostId: UUID) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: hostId.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain 保存失败: \(s)"
        case .notFound:          return "Keychain 中找不到凭据"
        }
    }
}
