import Foundation
import FTPunkIntegrations

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static var versionLabel: String { "Version \(version) · Build \(build)" }
    static var userAgent: String {
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        return IntervalsClient.userAgent(version: version, platform: platform)
    }
    static var intervalsClient: IntervalsClient { IntervalsClient(userAgent: userAgent) }
    static let credits = "Created by Kordian Gontarska · Developed with OpenAI Codex and Anthropic Claude"
}
