import Foundation
import FTPunkDomain
import FTPunkStorage

/// Only used with the explicit, isolated preview walkthrough launch arguments.
@MainActor enum PreviewFixtures {
    static func seed(_ store: LocalStore) throws {
        let alex = RiderProfile(name: "Alex", weightKG: 75)
        let sam = RiderProfile(id: UUID(), name: "Sam", weightKG: 55)
        try store.saveProfile(alex); try store.saveProfile(sam)
        for (rider, days, scale) in [(alex, 21.0, 0.94), (alex, 7.0, 0.98), (sam, 14.0, 0.85)] {
            let configuration = try SessionConfiguration(preset: rider.id == sam.id ? .gentle : .standard,
                weightKG: rider.weightKG, warmupSeconds: 10, cooldownSeconds: 10, riderID: rider.id, riderName: rider.name)
            var engine = RampEngine(configuration: configuration, isDemo: true, date: Date().addingTimeInterval(-days * 86400))
            var stream = MockRideStream()
            for index in 1...3600 where engine.phase.isActive {
                let time = Double(index) / 2
                let target = engine.targetPower ?? configuration.warmupPower
                engine.receive(stream.sample(at: time, target: target, phase: engine.phase, manualPower: Double(target) * scale))
                engine.tick(at: time)
            }
            try store.save(engine.session)
        }
    }
}
