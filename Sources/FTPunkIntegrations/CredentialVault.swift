import Foundation
import Security

public struct IntervalsConnection: Codable, Sendable {
    public let athleteID: String
    public let athleteName: String
    public let usesOAuth: Bool
    public let scopes: [String]?
    public var canReadCalendar: Bool { !usesOAuth || scopes?.contains("CALENDAR:READ") == true }
    /// Reading FTP and weight needs the athlete record. API keys can; OAuth tokens only with SETTINGS:READ.
    public var canReadAthleteSettings: Bool { !usesOAuth || scopes?.contains("SETTINGS:READ") == true }
    private let secret: String
    public var authorizationHeader: String {
        usesOAuth ? "Bearer " + secret : "Basic " + Data("API_KEY:\(secret)".utf8).base64EncodedString()
    }
    public init(athleteID: String, athleteName: String, apiKey: String) {
        self.athleteID = athleteID; self.athleteName = athleteName; secret = apiKey; usesOAuth = false; scopes = nil
    }
    public init(athleteID: String, athleteName: String, accessToken: String, scopes: [String]? = nil) {
        self.athleteID = athleteID; self.athleteName = athleteName; secret = accessToken; usesOAuth = true; self.scopes = scopes
    }
    private enum CodingKeys: String, CodingKey { case athleteID, athleteName, secret, usesOAuth, apiKey, scopes }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        athleteID = try values.decode(String.self, forKey: .athleteID)
        athleteName = try values.decode(String.self, forKey: .athleteName)
        scopes = try values.decodeIfPresent([String].self, forKey: .scopes)
        usesOAuth = try values.decodeIfPresent(Bool.self, forKey: .usesOAuth) ?? false
        secret = try values.decodeIfPresent(String.self, forKey: .secret) ?? values.decode(String.self, forKey: .apiKey)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(athleteID, forKey: .athleteID); try values.encode(athleteName, forKey: .athleteName)
        try values.encodeIfPresent(scopes, forKey: .scopes)
        try values.encode(usesOAuth, forKey: .usesOAuth); try values.encode(secret, forKey: .secret)
    }
}

public enum CredentialError: Error, LocalizedError {
    case keychain(OSStatus)
    public var errorDescription: String? { "The secure credential store could not be accessed." }
}

/// Where Intervals.icu connections live: one per rider. Tests use `InMemoryCredentialVault`.
public protocol CredentialStoring {
    func load(riderID: UUID) throws -> IntervalsConnection?
    func save(_ connection: IntervalsConnection, riderID: UUID) throws
    func clear(riderID: UUID) throws
    func allRiderIDs() throws -> [UUID]
    /// The app-wide connection of earlier versions (`personal-connection`). Only the one-time migration reads it.
    func loadLegacy() throws -> IntervalsConnection?
    func clearLegacy() throws
}

public extension CredentialStoring {
    /// Moves the app-wide connection of earlier versions to `riderID`. Safe to repeat: with nothing to move it does
    /// nothing, and a rider who already has a connection keeps it. Returns the connection that was moved, if any.
    @discardableResult func migrateLegacyConnection(to riderID: UUID) throws -> IntervalsConnection? {
        guard let legacy = try loadLegacy() else { return nil }
        if try load(riderID: riderID) == nil { try save(legacy, riderID: riderID) }
        try clearLegacy()
        return legacy
    }
}

public struct CredentialVault: CredentialStoring {
    private static let service = "app.ftpunk.intervals"
    private static let legacyAccount = "personal-connection"
    private static let riderPrefix = "rider:"
    public init() {}
    public static func account(for riderID: UUID) -> String { riderPrefix + riderID.uuidString.lowercased() }
    /// `rider:<uuid>` -> the rider's ID. Anything else (including the legacy account) is not a rider connection.
    public static func riderID(fromAccount account: String) -> UUID? {
        account.hasPrefix(riderPrefix) ? UUID(uuidString: String(account.dropFirst(riderPrefix.count))) : nil
    }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
    }
    private func load(account: String) throws -> IntervalsConnection? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialError.keychain(status) }
        return try JSONDecoder().decode(IntervalsConnection.self, from: data)
    }
    private func clear(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
    public func load(riderID: UUID) throws -> IntervalsConnection? { try load(account: Self.account(for: riderID)) }
    public func save(_ connection: IntervalsConnection, riderID: UUID) throws {
        let data = try JSONEncoder().encode(connection)
        let account = Self.account(for: riderID)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError.keychain(added) }
        } else if status != errSecSuccess { throw CredentialError.keychain(status) }
    }
    public func clear(riderID: UUID) throws { try clear(account: Self.account(for: riderID)) }
    public func allRiderIDs() throws -> [UUID] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
        q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw CredentialError.keychain(status) }
        return items.compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(Self.riderID(fromAccount:)) }
    }
    public func loadLegacy() throws -> IntervalsConnection? { try load(account: Self.legacyAccount) }
    public func clearLegacy() throws { try clear(account: Self.legacyAccount) }
}

/// Keeps connections in memory only. Used by previews and tests so they never touch the real Keychain.
public final class InMemoryCredentialVault: CredentialStoring, @unchecked Sendable {
    private var riders: [UUID: IntervalsConnection] = [:]
    private var legacy: IntervalsConnection?
    public init(legacy: IntervalsConnection? = nil, riders: [UUID: IntervalsConnection] = [:]) { self.legacy = legacy; self.riders = riders }
    public func load(riderID: UUID) throws -> IntervalsConnection? { riders[riderID] }
    public func save(_ connection: IntervalsConnection, riderID: UUID) throws { riders[riderID] = connection }
    public func clear(riderID: UUID) throws { riders[riderID] = nil }
    public func allRiderIDs() throws -> [UUID] { Array(riders.keys) }
    public func loadLegacy() throws -> IntervalsConnection? { legacy }
    public func clearLegacy() throws { legacy = nil }
}
