import Foundation
import CryptoKit
import Security

public enum OAuthError: Error, LocalizedError, Equatable {
    case notConfigured, invalidConfiguration, randomGeneration, invalidCallback, denied, missingPermission
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Intervals.icu sign-in will be available once FTPunk's app registration is approved."
        case .invalidConfiguration: "FTPunk's sign-in configuration is invalid."
        case .randomGeneration: "Unable to prepare a secure sign-in session. Please try again."
        case .invalidCallback: "The sign-in response could not be verified. Please try again."
        case .denied: "Intervals.icu access was not granted. You can connect again whenever you like."
        case .missingPermission: "Allow activity upload on the Intervals.icu consent screen to connect FTPunk."
        }
    }
}

public struct IntervalsOAuthConfiguration: Sendable {
    public let clientID: String
    public let redirectURI: URL
    public init(clientID: String, redirectURI: URL) throws {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              redirectURI.scheme == "ftpunk", redirectURI.host == "oauth",
              redirectURI.path == "/intervals", redirectURI.query == nil, redirectURI.fragment == nil else {
            throw OAuthError.invalidConfiguration
        }
        self.clientID = clientID; self.redirectURI = redirectURI
    }
}

public struct IntervalsOAuthAttempt: Sendable {
    public let configuration: IntervalsOAuthConfiguration
    public let verifier: String
    public let state: String
    public init(configuration: IntervalsOAuthConfiguration) throws {
        self.configuration = configuration
        verifier = try Self.randomToken(); state = try Self.randomToken()
    }
    /// Deterministic initializer for protocol fixtures, not used by the sign-in UI.
    public init(configuration: IntervalsOAuthConfiguration, verifier: String, state: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard (43...128).contains(verifier.count), verifier.unicodeScalars.allSatisfy(allowed.contains), !state.isEmpty else {
            throw OAuthError.invalidConfiguration
        }
        self.configuration = configuration; self.verifier = verifier; self.state = state
    }
    public var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public var authorizationURL: URL {
        var url = URLComponents(string: "https://intervals.icu/oauth/authorize")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "ACTIVITY:WRITE"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return url.url!
    }
    public func authorizationCode(from callback: URL) throws -> String {
        guard callback.scheme == configuration.redirectURI.scheme, callback.host == configuration.redirectURI.host,
              callback.path == configuration.redirectURI.path, callback.fragment == nil,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw OAuthError.invalidCallback }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states.first?.value == state else { throw OAuthError.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw OAuthError.denied }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty else { throw OAuthError.invalidCallback }
        return code
    }
    public func tokenRequest(code: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let values = [
            ("client_id", configuration.clientID), ("code", code), ("code_verifier", verifier),
            ("redirect_uri", configuration.redirectURI.absoluteString), ("grant_type", "authorization_code")
        ]
        request.httpBody = Data(values.map { Self.encoded($0.0) + "=" + Self.encoded($0.1) }.joined(separator: "&").utf8)
        return request
    }
    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
    }
    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw OAuthError.randomGeneration }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
