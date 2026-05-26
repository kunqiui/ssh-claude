import Foundation
import Combine

/// iPhone 端的连接池。每个 HostInfo 对应一个 SSHClient，按需连接，空闲不断开。
@MainActor
public class ConnectionManager: ObservableObject {
    public static let shared = ConnectionManager()
    private init() {}

    @Published public var hosts: [HostInfo] = []
    @Published public var activeConnections: Set<UUID> = []
    @Published public var error: String?

    private var clients: [UUID: SSHClient] = [:]
    private var tmuxManagers: [UUID: TmuxManager] = [:]

    // MARK: - Host 管理

    public func addHost(_ host: HostInfo, password: String) throws {
        try KeychainStore.save(hostId: host.id, password: password)
        hosts.append(host)
        saveHosts()
    }

    public func removeHost(_ host: HostInfo) {
        KeychainStore.delete(hostId: host.id)
        hosts.removeAll { $0.id == host.id }
        clients[host.id] = nil
        tmuxManagers[host.id] = nil
        saveHosts()
    }

    // MARK: - 连接

    public func connect(hostId: UUID) async throws {
        guard let host = hosts.first(where: { $0.id == hostId }) else { return }
        if activeConnections.contains(hostId) { return }
        let password = try KeychainStore.load(hostId: hostId)
        let client = SSHClient(host: host.host, port: host.port,
                               username: host.username, password: password)
        try await client.connect()
        clients[hostId] = client
        tmuxManagers[hostId] = TmuxManager(ssh: client)
        activeConnections.insert(hostId)
    }

    public func disconnect(hostId: UUID) async {
        await clients[hostId]?.disconnect()
        clients[hostId] = nil
        tmuxManagers[hostId] = nil
        activeConnections.remove(hostId)
    }

    // MARK: - Tmux 操作（供 WatchBridge 调用）

    public func listSessions(hostId: UUID) async throws -> [TmuxSession] {
        try await ensureConnected(hostId: hostId)
        return try await tmux(hostId).list()
    }

    public func attachSession(hostId: UUID, sessionName: String) async throws {
        try await ensureConnected(hostId: hostId)
        try await tmux(hostId).ensureSession(name: sessionName, command: "claude")
    }

    public func capturePane(hostId: UUID, sessionName: String) async throws -> String {
        try await ensureConnected(hostId: hostId)
        return try await tmux(hostId).capturePane(session: sessionName)
    }

    public func sendInput(hostId: UUID, sessionName: String, text: String, submit: Bool) async throws {
        try await ensureConnected(hostId: hostId)
        try await tmux(hostId).sendInput(session: sessionName, text: text, submit: submit)
    }

    public func sendKey(hostId: UUID, sessionName: String, key: SpecialKey) async throws {
        try await ensureConnected(hostId: hostId)
        try await tmux(hostId).sendKey(session: sessionName, key: key)
    }

    // MARK: - Persistence

    private let hostsKey = "saved_hosts"

    private func saveHosts() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: hostsKey)
        }
    }

    public func loadHosts() {
        guard let data = UserDefaults.standard.data(forKey: hostsKey),
              let saved = try? JSONDecoder().decode([HostInfo].self, from: data) else { return }
        hosts = saved
    }

    // MARK: - Helpers

    private func ensureConnected(hostId: UUID) async throws {
        if !activeConnections.contains(hostId) {
            try await connect(hostId: hostId)
        }
    }

    private func tmux(_ hostId: UUID) -> TmuxManager {
        tmuxManagers[hostId]!
    }
}
