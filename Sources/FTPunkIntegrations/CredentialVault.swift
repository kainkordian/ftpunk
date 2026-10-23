import Foundation
import Security

public struct IntervalsConnection: Codable, Sendable {
    public let athleteID: String
    public let athleteName: String
    public let apiKey: String
    public init(athleteID: String, athleteName: String, apiKey: String) {
        self.athleteID = athleteID; self.athleteName = athleteName; self.apiKey = apiKey
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
