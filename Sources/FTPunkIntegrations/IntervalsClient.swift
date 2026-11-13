import Foundation
import CoreFoundation
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
    private let userAgent: String
    public static let defaultUserAgent = "FTPunk"
    /// `FTPunk/<marketing version> (<iOS|macOS>)`. Intervals.icu answers requests without a client User-Agent with HTTP 403.
    public static func userAgent(version: String, platform: String) -> String { "FTPunk/\(version) (\(platform))" }
    public init(session: URLSession = .shared, userAgent: String = IntervalsClient.defaultUserAgent) {
        self.session = session; self.userAgent = userAgent
    }

    /// Advanced personal-use fallback. The normal connection flow uses OAuth + PKCE.
    public func connect(apiKey: String) async throws -> IntervalsConnection {
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/v1/athlete/0")!)
        request.setValue(Self.authorization(apiKey), forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        struct Athlete: Decodable { let id: String; let name: String? }
        let athlete = try JSONDecoder().decode(Athlete.self, from: data)
        return IntervalsConnection(athleteID: athlete.id, athleteName: athlete.name ?? athlete.id, apiKey: apiKey)
    }
    public func exchange(_ attempt: IntervalsOAuthAttempt, code: String) async throws -> IntervalsConnection {
        let (data, response) = try await session.data(for: Self.exchangeRequest(attempt, code: code, userAgent: userAgent))
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
                                   accessToken: token.access_token, scopes: scopes)
    }
    public nonisolated static func exchangeRequest(_ attempt: IntervalsOAuthAttempt, code: String, userAgent: String = defaultUserAgent) -> URLRequest {
        var request = attempt.tokenRequest(code: code)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
    /// FTP and weight from the athlete record. A 401/403 throws `IntervalsError.authentication`
    /// (the token may lack SETTINGS:READ); callers treat that as "skip", not as a broken connection.
    public func athleteSettings(connection: IntervalsConnection) async throws -> IntervalsAthleteSettings {
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/v1/athlete/0")!); request.timeoutInterval = 30
        request.setValue(connection.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try Self.decodeAthleteSettings(data)
    }
    public nonisolated static func decodeAthleteSettings(_ data: Data) throws -> IntervalsAthleteSettings {
        guard data.count <= 2 * 1024 * 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw IntervalsError.invalidResponse }
        return IntervalsAthleteSettings.decode(object)
    }
    public nonisolated static func workoutRequest(connection: IntervalsConnection, oldest: String, newest: String, userAgent: String = defaultUserAgent) throws -> URLRequest {
        guard connection.canReadCalendar else { throw ArchiveError.invalid("Reconnect Intervals.icu and allow calendar read access to download workouts.") }
        var url = URLComponents(string: "https://intervals.icu/api/v1/athlete/0/events")!
        url.queryItems = [URLQueryItem(name: "category", value: "WORKOUT"), URLQueryItem(name: "resolve", value: "true"), URLQueryItem(name: "oldest", value: oldest), URLQueryItem(name: "newest", value: newest)]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30
        request.setValue(connection.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
    public func workouts(connection: IntervalsConnection, riderID: UUID, ftp: Double?, oldest: String, newest: String) async throws -> (workouts: [CachedWorkout], skipped: [String]) {
        let (data, response) = try await session.data(for: Self.workoutRequest(connection: connection, oldest: oldest, newest: newest, userAgent: userAgent))
        try Self.validate(response)
        return try Self.decodeWorkouts(data, accountID: connection.athleteID, riderID: riderID, ftp: ftp)
    }
    public nonisolated static func decodeWorkouts(_ data: Data, accountID: String, riderID: UUID, ftp: Double?) throws -> (workouts: [CachedWorkout], skipped: [String]) {
        guard data.count <= 10 * 1024 * 1024, let events = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], events.count <= 1000 else { throw IntervalsError.invalidResponse }
        var workouts: [CachedWorkout] = [], skipped: [String] = []
        for event in events {
            guard CalendarWorkoutPolicy.qualifies(event) else { continue }
            let name = event["name"] as? String ?? "Untitled workout"
            do {
                let rawID: String
                if let id = event["id"] as? String { rawID = id }
                else if let id = event["id"] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(), id.doubleValue.isFinite, id.doubleValue.rounded() == id.doubleValue { rawID = id.stringValue }
                else { throw IntervalsError.invalidResponse }
                guard !rawID.isEmpty, rawID.count <= 80 else { throw IntervalsError.invalidResponse }
                // The file importer accepts Ride only. Calendar cycling also includes VirtualRide;
                // normalize this copy without changing file-import behaviour.
                var cyclingEvent = event
                cyclingEvent["type"] = "Ride"
                let plan = try WorkoutImport.parse(JSONSerialization.data(withJSONObject: cyclingEvent), ftp: ftp)
                workouts.append(CachedWorkout(id: "intervals:\(accountID):\(riderID.uuidString.lowercased()):\(rawID)", riderID: riderID, source: "Intervals.icu · \(name)", plan: plan,
                                              scheduledDate: ScheduledDate.from(intervalsLocal: event["start_date_local"] as? String)))
            } catch { skipped.append("\(name): \(error.localizedDescription)") }
        }
        return (workouts, skipped)
    }
    public func revoke(_ connection: IntervalsConnection) async throws {
        guard connection.usesOAuth else { return }
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/v1/disconnect-app")!)
        request.httpMethod = "DELETE"; request.timeoutInterval = 15
        request.setValue(connection.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 401 else {
            throw IntervalsError.invalidResponse
        }
    }
    public func upload(_ job: ActivityUploadJob, credential: String) async throws -> [String] {
        let request = Self.uploadRequest(job, credential: credential, userAgent: userAgent)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        // A 200 response can acknowledge a duplicate of an earlier accepted upload.
        // IDs are optional metadata; acceptance is based on the upload HTTP status.
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return Self.activityIDs(value)
    }
    public nonisolated static func uploadRequest(_ job: ActivityUploadJob, credential: String, userAgent: String = defaultUserAgent) -> URLRequest {
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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let file = ActivityUploadFile.make(sessionID: job.sessionID, bytes: job.file)
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.name)\"\r\nContent-Type: \(file.mediaType)\r\n\r\n".utf8)
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
