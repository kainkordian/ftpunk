import Foundation
import Testing
import FTPunkDomain
@testable import FTPunkStorage

// Shared FIT fixtures for the web app (plan 9b). Two fixed sessions are encoded by `FITEncoder` and written, with their session JSON, to
// contracts/fixtures/. The JavaScript encoder (ftpunk_web/src/fit.mjs) must produce byte-identical files from the same session JSON.
// Regenerate with: FTPUNK_WRITE_FIXTURES=1 swift test --filter fitFilesMatchTheSharedFixtures
//
// The activity message carries the local time zone offset (`local_timestamp`). It is written next to the files (`fit-offsets.json`) and the web test
// passes it to its encoder. On a machine in another time zone only those four bytes (and the file CRC) may differ.

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let shared = root.appendingPathComponent("contracts/fixtures")
private let webCopy = root.appendingPathComponent("ftpunk_web/tests/fixtures")
private let start = Date(timeIntervalSince1970: 1_793_700_000)
private let rider = UUID(uuidString: "A1E00000-0000-4000-8000-000000000001")!

private func configuration(power: PowerSource, cadence: CadenceSource) throws -> SessionConfiguration {
    try SessionConfiguration(priorFTP: FTPEntry(id: UUID(uuidString: "F7000000-0000-4000-8000-000000000230")!, watts: 230, date: start, source: "Manual"),
                             weightKG: 71, riderID: rider, riderName: "Alex", powerSource: power, cadenceSource: cadence)
}

/// An FTP test with an external power meter and a heart-rate strap. Each second has up to three notifications (meter, trainer, strap), a few
/// seconds have no value at all, and the strap only starts after ten seconds.
private func rampSession() throws -> TestSession {
    var session = TestSession(id: UUID(uuidString: "5EED0001-0000-4000-8000-00000000F001")!, startedAt: start, configuration: try configuration(power: .externalPowerMeter, cadence: .externalPowerMeter))
    for second in 0...420 {
        let t = Double(second)
        if second % 97 == 50 { continue } // a dropout: no record for this second
        let watts = Double(100 + second / 2)
        session.samples.append(RideSample(time: t, power: watts, cadence: 88 + Double(second % 5), leftBalance: 47.5 + Double(second % 7)))
        session.samples.append(RideSample(time: t + 0.4, trainerPower: watts + 4.4))
        if second >= 10 { session.samples.append(RideSample(time: t + 0.7, heartRate: 118 + second / 8)) }
    }
    session.events = [SessionEvent(time: 0, message: "Start pedaling"), SessionEvent(time: 60, message: "Ramp test"), SessionEvent(time: 360, message: "Cooldown")]
    session.rampStart = 60; session.rampEnd = 360; session.endedAtOffset = 420; session.outcome = .exhaustion
    session.result = FTPResult(bestMinutePower: 300, windowStart: 299, windowEnd: 359)
    return session
}

/// A workout with trainer power only, one pause (release confirmed 401, resumed 460) and three steps.
private func workoutSession() throws -> TestSession {
    let plan = try TrainingPlan(kind: .workout, name: "Sweet spot", ftpWatts: 230, steps: [
        .init("Warm-up", seconds: 300, watts: 115), .init("Work", seconds: 300, watts: 207), .init("Cool-down", seconds: 300, watts: 115)])
    var session = TestSession(id: UUID(uuidString: "5EED0002-0000-4000-8000-00000000F002")!, startedAt: start, configuration: try configuration(power: .trainer, cadence: .trainer))
    session.training = plan
    session.events = [SessionEvent(time: 5, message: "Training"),
                      SessionEvent(time: 400, message: "Training paused; trainer release requested"),
                      SessionEvent(time: 401, message: "Trainer release confirmed for pause"),
                      SessionEvent(time: 460, message: "Training resumed")]
    for second in 0...964 {
        session.samples.append(RideSample(time: Double(second), power: Double(second < 305 ? 115 : second < 605 ? 207 : 115) + Double(second % 3), cadence: 85 + Double(second % 4)))
    }
    session.endedAtOffset = 964; session.outcome = .completed
    return session
}

private struct Fixture { let name: String; let session: TestSession }

@Test func fitFilesMatchTheSharedFixtures() throws {
    let fixtures = [Fixture(name: "ftp-test", session: try rampSession()), Fixture(name: "workout", session: try workoutSession())]
    let writing = ProcessInfo.processInfo.environment["FTPUNK_WRITE_FIXTURES"] == "1"
    let offsetsURL = shared.appendingPathComponent("fit-offsets.json")
    var offsets: [String: Int] = [:]
    for fixture in fixtures {
        let end = try #require(fixture.session.endedAtOffset)
        offsets[fixture.name] = TimeZone.current.secondsFromGMT(for: fixture.session.startedAt.addingTimeInterval(end))
    }
    let fitData = try Dictionary(uniqueKeysWithValues: fixtures.map { ($0.name, try FITEncoder.fileData($0.session)) })
    let jsonData = try Dictionary(uniqueKeysWithValues: fixtures.map { ($0.name, try ActivityExport.json($0.session)) })
    if writing {
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        for fixture in fixtures {
            try fitData[fixture.name]!.write(to: shared.appendingPathComponent("fit-\(fixture.name).fit"), options: .atomic)
            try jsonData[fixture.name]!.write(to: shared.appendingPathComponent("fit-\(fixture.name).session.json"), options: .atomic)
        }
        try JSONSerialization.data(withJSONObject: ["utcOffsetSeconds": offsets], options: [.prettyPrinted, .sortedKeys]).write(to: offsetsURL, options: .atomic)
    }
    let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: offsetsURL)) as? [String: [String: Int]])["utcOffsetSeconds"]
    for fixture in fixtures {
        let hint = "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter fitFilesMatchTheSharedFixtures"
        let storedFIT = try Data(contentsOf: shared.appendingPathComponent("fit-\(fixture.name).fit"))
        let storedJSON = try Data(contentsOf: shared.appendingPathComponent("fit-\(fixture.name).session.json"))
        #expect(storedJSON == jsonData[fixture.name], Comment(rawValue: "\(fixture.name) session JSON. \(hint)"))
        let fresh = try #require(fitData[fixture.name])
        if stored?[fixture.name] == offsets[fixture.name] {
            #expect(storedFIT == fresh, Comment(rawValue: "\(fixture.name) FIT bytes. \(hint)"))
        } else {
            // Another time zone: only the activity message's local_timestamp (the last four data bytes) and the file CRC may differ.
            #expect(storedFIT.count == fresh.count && storedFIT.dropLast(6) == fresh.dropLast(6), Comment(rawValue: "\(fixture.name) FIT bytes outside the time zone field. \(hint)"))
        }
        #expect(FITEncoder.crc16(fresh.dropLast(2)) == UInt16(fresh[fresh.count - 2]) | UInt16(fresh[fresh.count - 1]) << 8)
        // The web app keeps byte-identical copies so its suite stays self-contained.
        for file in ["fit-\(fixture.name).fit", "fit-\(fixture.name).session.json"] {
            let copy = try Data(contentsOf: webCopy.appendingPathComponent(file))
            #expect(copy == (try Data(contentsOf: shared.appendingPathComponent(file))), Comment(rawValue: "ftpunk_web/tests/fixtures/\(file) differs from contracts/fixtures/\(file); copy it again"))
        }
    }
    #expect((try Data(contentsOf: webCopy.appendingPathComponent("fit-offsets.json"))) == (try Data(contentsOf: offsetsURL)))
}
