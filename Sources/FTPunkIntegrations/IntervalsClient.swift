import Foundation
import FTPunkDomain

public enum IntervalsError: Error, LocalizedError {
    case authentication, http(Int, retryAfter: TimeInterval?), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .authentication: "Reconnect your Intervals.icu account."
        case .http(let status, _): "Intervals.icu returned HTTP \(status)."
        case .invalidResponse: "Intervals.icu returned an unexpected response."
        }
    }
    public var retryDelay: TimeInterval? {
        if case .http(let code, let delay) = self, code == 429 || code >= 500 { return delay ?? 60 }
        return nil
    }
}

public actor IntervalsClient: ActivityUploader {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    /// Advanced personal-use fallback. The normal connection flow uses OAuth + PKCE.
    public func connect(apiKey: String) async throws -> IntervalsConnection {
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/v1/athlete/0")!)
        request.setValue(Self.authorization(apiKey), forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        struct Athlete: Decodable { let id: String; let name: String? }
        let athlete = try JSONDecoder().decode(Athlete.self, from: data)
        return IntervalsConnection(athleteID: athlete.id, athleteName: athlete.name ?? athlete.id, apiKey: apiKey)
    }
    public func exchange(_ attempt: IntervalsOAuthAttempt, code: String) async throws -> IntervalsConnection {
        let (data, response) = try await session.data(for: attempt.tokenRequest(code: code))
        try Self.validate(response)
        struct Token: Decodable {
            let access_token: String
            let token_type: String
            let scope: String
            let athlete: Athlete
            struct Athlete: Decodable { let id: String; let name: String? }
        }
        let token = try JSONDecoder().decode(Token.self, from: data)
        guard token.token_type.lowercased() == "bearer", !token.access_token.isEmpty else { throw IntervalsError.invalidResponse }
        let scopes = token.scope.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard scopes.contains("ACTIVITY:WRITE") else { throw OAuthError.missingPermission }
        return IntervalsConnection(athleteID: token.athlete.id, athleteName: token.athlete.name ?? token.athlete.id,
                                   accessToken: token.access_token)
    }
    public func revoke(_ connection: IntervalsConnection) async throws {
        guard connection.usesOAuth else { return }
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/v1/disconnect-app")!)
        request.httpMethod = "DELETE"; request.timeoutInterval = 15
        request.setValue(connection.authorizationHeader, forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 401 else {
            throw IntervalsError.invalidResponse
        }
    }
    public func upload(_ job: ActivityUploadJob, credential: String) async throws -> [String] {
        let request = Self.uploadRequest(job, credential: credential)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        // A 200 response can acknowledge a duplicate of an earlier accepted upload.
        // IDs are optional metadata; acceptance is based on the upload HTTP status.
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return Self.activityIDs(value)
    }
    public nonisolated static func uploadRequest(_ job: ActivityUploadJob, credential: String) -> URLRequest {
        var components = URLComponents(string: "https://intervals.icu/api/v1/athlete/0/activities")!
        components.queryItems = [
            URLQueryItem(name: "external_id", value: "ftpunk-\(job.sessionID.uuidString)"),
            URLQueryItem(name: "name", value: job.name),
            URLQueryItem(name: "description", value: job.description),
            URLQueryItem(name: "device_name", value: "FTPunk")
        ]
        var request = URLRequest(url: components.url!); request.httpMethod = "POST"; request.timeoutInterval = 60
        let boundary = "FTPunk-\(job.id.uuidString)"
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(job.sessionID.uuidString).tcx\"\r\nContent-Type: application/vnd.garmin.tcx+xml\r\n\r\n".utf8)
        body.append(job.file); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body; return request
    }
    private nonisolated static func authorization(_ key: String) -> String {
        "Basic " + Data("API_KEY:\(key)".utf8).base64EncodedString()
    }
    private nonisolated static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw IntervalsError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw IntervalsError.authentication }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            throw IntervalsError.http(http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        }
    }
    private nonisolated static func activityIDs(_ value: Any) -> [String] {
        if let list = value as? [Any] { return list.flatMap(activityIDs) }
        guard let object = value as? [String: Any] else { return [] }
        if let id = object["id"] as? String, id.hasPrefix("i") { return [id] }
        return object.values.flatMap(activityIDs)
    }
}
