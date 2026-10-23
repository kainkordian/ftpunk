import Foundation
import Security

public struct IntervalsConnection: Codable, Sendable {
    public let athleteID: String
    public let athleteName: String
    public let usesOAuth: Bool
    private let secret: String
    public var authorizationHeader: String {
        usesOAuth ? "Bearer " + secret : "Basic " + Data("API_KEY:\(secret)".utf8).base64EncodedString()
    }
    public init(athleteID: String, athleteName: String, apiKey: String) {
        self.athleteID = athleteID; self.athleteName = athleteName; secret = apiKey; usesOAuth = false
    }
    public init(athleteID: String, athleteName: String, accessToken: String) {
        self.athleteID = athleteID; self.athleteName = athleteName; secret = accessToken; usesOAuth = true
    }
    private enum CodingKeys: String, CodingKey { case athleteID, athleteName, secret, usesOAuth, apiKey }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        athleteID = try values.decode(String.self, forKey: .athleteID)
        athleteName = try values.decode(String.self, forKey: .athleteName)
        usesOAuth = try values.decodeIfPresent(Bool.self, forKey: .usesOAuth) ?? false
        secret = try values.decodeIfPresent(String.self, forKey: .secret) ?? values.decode(String.self, forKey: .apiKey)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(athleteID, forKey: .athleteID); try values.encode(athleteName, forKey: .athleteName)
        try values.encode(usesOAuth, forKey: .usesOAuth); try values.encode(secret, forKey: .secret)
    }
}

public enum CredentialError: Error, LocalizedError {
    case keychain(OSStatus)
    public var errorDescription: String? { "The secure credential store could not be accessed." }
}

public enum CredentialVault {
    private static let service = "app.ftpunk.intervals"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "personal-connection"]
    }
    public static func load() throws -> IntervalsConnection? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialError.keychain(status) }
        return try JSONDecoder().decode(IntervalsConnection.self, from: data)
    }
    public static func save(_ connection: IntervalsConnection) throws {
        let data = try JSONEncoder().encode(connection)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError.keychain(added) }
        } else if status != errSecSuccess { throw CredentialError.keychain(status) }
    }
    public static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
}
