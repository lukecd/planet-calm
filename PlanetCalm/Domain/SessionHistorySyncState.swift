import CryptoKit
import Foundation

/// A local-only account key derived from CloudKit's private-database user record.
/// It is never used as a CloudKit record name or uploaded as session data.
struct SessionHistoryAccountKey: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(userRecordName: String) {
        self.rawValue = userRecordName
    }

    var safeFileComponent: String {
        SHA256.hash(data: Data(rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// All mutable sync state for one private iCloud account. Its ownership is
/// verified before it is read or written by a future CloudKit adapter.
struct SessionHistoryAccountState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    let accountKey: SessionHistoryAccountKey
    var isEnabled: Bool
    var serverRecords: [String: Data] = [:]
    var engineStateData: Data?
    var pendingUploadIDs: Set<UUID>
    var remoteInbox: [SessionHistoryRemoteInboxEntry]
    var lastSuccessfulSyncAt: Date?

    init(
        accountKey: SessionHistoryAccountKey,
        isEnabled: Bool = false,
        engineStateData: Data? = nil,
        pendingUploadIDs: Set<UUID> = [],
        remoteInbox: [SessionHistoryRemoteInboxEntry] = [],
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.accountKey = accountKey
        self.isEnabled = isEnabled
        self.engineStateData = engineStateData
        self.pendingUploadIDs = pendingUploadIDs
        self.remoteInbox = remoteInbox
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, accountKey, isEnabled, serverRecords, engineStateData
        case pendingUploadIDs, remoteInbox, lastSuccessfulSyncAt
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        accountKey = try values.decode(SessionHistoryAccountKey.self, forKey: .accountKey)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        serverRecords = try values.decodeIfPresent([String: Data].self, forKey: .serverRecords) ?? [:]
        engineStateData = try values.decodeIfPresent(Data.self, forKey: .engineStateData)
        pendingUploadIDs = try values.decode(Set<UUID>.self, forKey: .pendingUploadIDs)
        remoteInbox = try values.decode([SessionHistoryRemoteInboxEntry].self, forKey: .remoteInbox)
        lastSuccessfulSyncAt = try values.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
    }

}

/// Durable remote work. An adapter stores an entry before merging it into the
/// ledger, so a crash cannot advance the engine beyond unrecorded imports.
struct SessionHistoryRemoteInboxEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let receivedAt: Date
    let history: TerminalSessionHistoryExport

    init(id: UUID = UUID(), receivedAt: Date = .now, history: TerminalSessionHistoryExport) {
        self.id = id
        self.receivedAt = receivedAt
        self.history = history
    }
}

protocol SessionHistoryAccountStatePersistence: Sendable {
    func load(account: SessionHistoryAccountKey) async throws -> Data?
    func save(_ data: Data, account: SessionHistoryAccountKey) async throws
}

actor FileSessionHistoryAccountStatePersistence: SessionHistoryAccountStatePersistence {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    func load(account: SessionHistoryAccountKey) throws -> Data? {
        try read(from: accountURL(for: account))
    }

    func save(_ data: Data, account: SessionHistoryAccountKey) throws {
        try write(data, to: accountURL(for: account))
    }

    private func accountURL(for account: SessionHistoryAccountKey) -> URL {
        directory.appending(path: "account-\(account.safeFileComponent).json", directoryHint: .notDirectory)
    }

    private func read(from url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "PlanetFocus", directoryHint: .isDirectory)
            .appending(path: "session-history-sync", directoryHint: .isDirectory)
    }
}

actor SessionHistoryAccountStateStore {
    private let persistence: any SessionHistoryAccountStatePersistence

    init(persistence: any SessionHistoryAccountStatePersistence = FileSessionHistoryAccountStatePersistence()) {
        self.persistence = persistence
    }

    func load(for account: SessionHistoryAccountKey) async throws -> SessionHistoryAccountState {
        guard let data = try await persistence.load(account: account) else {
            return SessionHistoryAccountState(accountKey: account)
        }
        let state = try JSONDecoder().decode(SessionHistoryAccountState.self, from: data)
        guard state.schemaVersion == SessionHistoryAccountState.currentSchemaVersion,
              state.accountKey == account else {
            throw SessionLedgerError.corruptStore
        }
        return state
    }

    func save(_ state: SessionHistoryAccountState) async throws {
        guard state.schemaVersion == SessionHistoryAccountState.currentSchemaVersion else {
            throw SessionLedgerError.unsupportedSchema(state.schemaVersion)
        }
        try await persistence.save(JSONEncoder().encode(state), account: state.accountKey)
    }
}
