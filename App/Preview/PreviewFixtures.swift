import Foundation
import FTPunkDomain
import FTPunkStorage

/// Deterministic riders and recordings for the in-memory preview store. Never used with the persistent store.
@MainActor enum PreviewFixtures {
    static let alexID = UUID(uuidString: "A1E00000-0000-4000-8000-000000000001")!
    static let samID = UUID(uuidString: "5A400000-0000-4000-8000-000000000002")!

    static func rider(id: UUID = alexID, name: String = "Alex", weightKG: Double? = 75, ftp: Double? = 250,
                      daysAgo: Int = 21, source: String = "Ramp test") -> RiderProfile {
        var rider = RiderProfile(id: id, name: name, weightKG: weightKG)
        if let ftp {
            let entry = FTPEntry(id: UUID(uuidString: "F7000000-0000-4000-8000-\(String(format: "%012d", Int(ftp)))")!, watts: ftp,
                                 date: Date().addingTimeInterval(-Double(daysAgo) * 86400), source: source)
            rider.ftpHistory = [entry]; rider.currentFTPID = entry.id
        }
        return rider
    }

    /// A finished ramp run through the real engine with mock input. `scale` shapes the power a rider holds.
    static func finishedRampEngine(for rider: RiderProfile, daysAgo: Double, scale: Double, demo: Bool = false,
                                   preset: RampPreset = .standard) throws -> RampEngine {
        let configuration = try SessionConfiguration(preset: preset, priorFTP: rider.currentFTP, weightKG: rider.weightKG,
                                                     warmupSeconds: 10, cooldownSeconds: 10, riderID: rider.id, riderName: rider.name)
        var engine = RampEngine(configuration: configuration, isDemo: demo, date: Date().addingTimeInterval(-daysAgo * 86400))
        var stream = MockRideStream()
        for index in 1...3600 where engine.phase.isActive {
            let time = Double(index) / 2
            let target = engine.targetPower ?? configuration.warmupPower
            engine.receive(stream.sample(at: time, target: target, phase: engine.phase, manualPower: Double(target) * scale))
            engine.tick(at: time)
        }
        return engine
    }
    static func finishedRamp(for rider: RiderProfile, daysAgo: Double, scale: Double, demo: Bool = false,
                             preset: RampPreset = .standard) throws -> TestSession {
        try finishedRampEngine(for: rider, daysAgo: daysAgo, scale: scale, demo: demo, preset: preset).session
    }

    /// Two riders with dated history, as used by the original walkthrough.
    static func seed(_ store: LocalStore, demo: Bool = true) throws {
        let alex = rider(), sam = rider(id: samID, name: "Sam", weightKG: 55, ftp: 180, daysAgo: 30)
        try store.saveProfile(alex); try store.saveProfile(sam)
        for (rider, days, scale, preset) in [(alex, 56.0, 0.94, RampPreset.standard), (alex, 21.0, 0.98, .standard), (sam, 14.0, 0.85, .gentle)] {
            try store.save(finishedRamp(for: rider, daysAgo: days, scale: scale, demo: demo, preset: preset))
        }
    }
}
