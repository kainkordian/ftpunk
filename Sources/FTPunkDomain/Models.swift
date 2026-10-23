import Foundation

public enum RampPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, gentle, zwift
    public var id: String { rawValue }
    public var title: String {
        switch self { case .standard: "25 W / min"; case .gentle: "15 W / min"; case .zwift: "20 W / min · Zwift-style" }
    }
    public var startingPower: Int { self == .gentle ? 50 : 100 }
    public var stepSeconds: Double {
        switch self { case .standard: 12; case .gentle: 20; case .zwift: 60 }
    }
    public var stepWatts: Int { self == .zwift ? 20 : 5 }
    public var cooldownPower: Int { self == .gentle ? 50 : 75 }
    public var fallbackWarmupPower: Int { self == .gentle ? 75 : 100 }
    public var summary: String { "Start at \(startingPower) W · +\(stepWatts) W every \(Int(stepSeconds)) s" }
    public var audience: String {
        switch self {
        case .gentle: "Lighter riders · reference guideline below 60 kg"
        case .standard: "Heavier riders · reference guideline 60 kg and above"
        case .zwift: "Legacy option from apps such as Zwift · one-minute steps"
        }
    }
}

public struct FTPEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var watts: Double
    public var date: Date
    public var source: String
    public init(id: UUID = UUID(), watts: Double, date: Date = Date(), source: String = "Manual") {
        self.id = id; self.watts = watts; self.date = date; self.source = source
    }
}

public enum ConfigurationError: Error, LocalizedError, Equatable {
    case invalidFTP, invalidWeight, invalidWarmup, invalidLimits, invalidRider
    public var errorDescription: String? {
        switch self {
        case .invalidFTP: "FTP must be a positive number."
        case .invalidWeight: "Weight must be a positive number in kg."
        case .invalidWarmup: "Enter a valid warm-up duration and power."
        case .invalidLimits: "The test limits must be above the starting target."
        case .invalidRider: "Enter a rider name (up to 80 characters)."
        }
    }
}

public struct SessionConfiguration: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let preset: RampPreset
    public let priorFTP: FTPEntry?
    public let weightKG: Double?
    public let warmupSeconds: Double
    public let warmupPower: Int
    public let usesAutomaticWarmup: Bool
    public let maximumPower: Int
    public let maximumRampSeconds: Double
    public let cooldownSeconds: Double
    public let ftpFactor: Double
    public let riderID: UUID?
    public let riderName: String?

    public init(preset: RampPreset = .standard, priorFTP: FTPEntry? = nil, weightKG: Double? = nil,
                warmupSeconds: Double = 600, manualWarmupPower: Int? = nil,
                maximumPower: Int = 600, maximumRampSeconds: Double = 1800,
                cooldownSeconds: Double = 180, ftpFactor: Double = 0.72,
                riderID: UUID? = nil, riderName: String? = nil) throws {
        if let riderName, riderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || riderName.count > 80 {
            throw ConfigurationError.invalidRider
        }
        if let ftp = priorFTP?.watts, !ftp.isFinite || ftp <= 0 { throw ConfigurationError.invalidFTP }
        if let weightKG, !weightKG.isFinite || weightKG <= 0 { throw ConfigurationError.invalidWeight }
        // Validate before converting a Double to Int, including values outside Int's range.
        let derived = priorFTP.map { $0.watts * 0.5 } ?? Double(preset.fallbackWarmupPower)
        guard derived.isFinite, derived > 0, derived <= 32767,
              warmupSeconds.isFinite, (0...3600).contains(warmupSeconds),
              manualWarmupPower.map({ (1...32767).contains($0) }) ?? true else {
            throw ConfigurationError.invalidWarmup
        }
        guard maximumPower >= preset.startingPower, maximumPower <= 32767,
              maximumRampSeconds.isFinite, maximumRampSeconds >= 60,
              cooldownSeconds.isFinite, cooldownSeconds >= 0, [0.72, 0.75].contains(ftpFactor) else { throw ConfigurationError.invalidLimits }
        self.protocolVersion = 2; self.preset = preset; self.priorFTP = priorFTP; self.weightKG = weightKG
        self.warmupSeconds = warmupSeconds; self.warmupPower = manualWarmupPower ?? Int(derived.rounded())
        self.usesAutomaticWarmup = manualWarmupPower == nil; self.maximumPower = maximumPower
        self.maximumRampSeconds = maximumRampSeconds; self.cooldownSeconds = cooldownSeconds; self.ftpFactor = ftpFactor
        self.riderID = riderID; self.riderName = riderName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func rampPower(at elapsed: Double) -> Int {
        let bounded = min(max(elapsed, 0), maximumRampSeconds)
        return min(maximumPower, preset.startingPower + Int(bounded / preset.stepSeconds) * preset.stepWatts)
    }
}

public struct PowerSample: Codable, Equatable, Sendable {
    public let time: Double
    public let watts: Double
    public init(time: Double, watts: Double) { self.time = time; self.watts = watts }
}

public struct RideSample: Codable, Equatable, Sendable {
    public var time: Double
    public var power: Double?
    public var cadence: Double?
    public var heartRate: Int?
    public var trainerPower: Double?
    public init(time: Double, power: Double? = nil, cadence: Double? = nil,
                heartRate: Int? = nil, trainerPower: Double? = nil) {
        self.time = time; self.power = power; self.cadence = cadence
        self.heartRate = heartRate; self.trainerPower = trainerPower
    }
}

public struct FTPResult: Codable, Equatable, Sendable {
    public let bestMinutePower: Double
    public let windowStart: Double
    public let windowEnd: Double
    public let factor: Double
    public let weightKG: Double?
    public let algorithmVersion: Int
    public var estimatedFTP: Double { bestMinutePower * factor }
    public var lowerFTP: Double { bestMinutePower * 0.72 }
    public var upperFTP: Double { bestMinutePower * 0.77 }
    public var wattsPerKG: Double? { weightKG.map { estimatedFTP / $0 } }
    public init(bestMinutePower: Double, windowStart: Double, windowEnd: Double,
                factor: Double = 0.72, weightKG: Double? = nil) {
        self.bestMinutePower = bestMinutePower; self.windowStart = windowStart; self.windowEnd = windowEnd
        self.factor = factor; self.weightKG = weightKG; self.algorithmVersion = 1
    }
}

public enum SessionOutcome: String, Codable, Sendable {
    case exhaustion, finishedEarly, limitReached, interrupted, aborted
    public var allowsEstimate: Bool { self == .exhaustion || self == .finishedEarly }
    public var title: String {
        switch self {
        case .exhaustion: "Ramp complete"
        case .finishedEarly: "Finished early"
        case .limitReached: "Test limit reached"
        case .interrupted: "Test interrupted"
        case .aborted: "Stopped"
        }
    }
}

public struct SessionEvent: Codable, Equatable, Sendable {
    public let time: Double
    public let message: String
    public init(time: Double, message: String) { self.time = time; self.message = message }
}

public struct DeviceSnapshot: Codable, Sendable {
    public let role: String
    public let name: String
    public let localIdentifier: String
    public let capabilities: [String: String]
    public init(role: String, name: String, localIdentifier: String, capabilities: [String: String] = [:]) {
        self.role = role; self.name = name; self.localIdentifier = localIdentifier; self.capabilities = capabilities
    }
}

public struct TestSession: Identifiable, Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var configuration: SessionConfiguration
    public var isDemo: Bool
    public var devices: [DeviceSnapshot]
    public var samples: [RideSample]
    public var events: [SessionEvent]
    public var outcome: SessionOutcome?
    public var endReason: String?
    public var rampStart: Double?
    public var rampEnd: Double?
    public var endedAtOffset: Double?
    public var result: FTPResult?
    public var riderID: UUID { configuration.riderID ?? RiderProfile.legacyID }
    public var riderName: String { configuration.riderName ?? "You" }
    public init(id: UUID = UUID(), startedAt: Date = Date(), configuration: SessionConfiguration, isDemo: Bool = false,
                devices: [DeviceSnapshot] = []) {
        self.id = id; self.startedAt = startedAt; self.configuration = configuration; self.isDemo = isDemo
        self.samples = []; self.events = []; self.devices = devices
    }
}

public struct RiderProfile: Identifiable, Codable, Sendable {
    public static let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public var id: UUID
    public var name: String
    public var weightKG: Double?
    public var ftpHistory: [FTPEntry]
    public var currentFTPID: UUID?
    public init(id: UUID = RiderProfile.legacyID, name: String = "You", weightKG: Double? = nil,
                ftpHistory: [FTPEntry] = [], currentFTPID: UUID? = nil) {
        self.id = id; self.name = name
        self.weightKG = weightKG; self.ftpHistory = ftpHistory; self.currentFTPID = currentFTPID
    }
    public var currentFTP: FTPEntry? { ftpHistory.first { $0.id == currentFTPID } }
    private enum CodingKeys: String, CodingKey { case id, name, weightKG, ftpHistory, currentFTPID }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? Self.legacyID
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "You"
        weightKG = try values.decodeIfPresent(Double.self, forKey: .weightKG)
        ftpHistory = try values.decode([FTPEntry].self, forKey: .ftpHistory)
        currentFTPID = try values.decodeIfPresent(UUID.self, forKey: .currentFTPID)
    }
}
