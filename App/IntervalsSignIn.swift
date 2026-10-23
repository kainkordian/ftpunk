import Foundation
import AuthenticationServices
import FTPunkIntegrations
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor final class IntervalsSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    static var configuration: IntervalsOAuthConfiguration? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "IntervalsOAuthClientID") as? String)
            .flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 }
            ?? ProcessInfo.processInfo.environment["FTPUNK_INTERVALS_CLIENT_ID"]
        guard let value else { return nil }
        return try? IntervalsOAuthConfiguration(clientID: value, redirectURI: URL(string: "ftpunk://oauth/intervals")!)
    }
    func connect() async throws -> IntervalsConnection {
        guard let configuration = Self.configuration else { throw OAuthError.notConfigured }
        let attempt = try IntervalsOAuthAttempt(configuration: configuration)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let browser = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: "ftpunk") { [weak self] url, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: OAuthError.invalidCallback) }
                }
            }
            browser.presentationContextProvider = self
            browser.prefersEphemeralWebBrowserSession = false
            session = browser
            if !browser.start() { session = nil; continuation.resume(throwing: OAuthError.invalidCallback) }
        }
        let code = try attempt.authorizationCode(from: callback)
        return try await IntervalsClient().exchange(attempt, code: code)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
