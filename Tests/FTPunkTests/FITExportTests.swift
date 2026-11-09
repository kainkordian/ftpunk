import Foundation
import Testing
import FTPunkDomain
@testable import FTPunkStorage

// MARK: A just-enough FIT decoder

private struct FITMessage { let global: Int; let fields: [Int: UInt64]; var arrays: [Int: [UInt64]] = [:] }
private struct FITFile {
    var headerSize = 0, protocolVersion = 0, profileVersion = 0, dataSize = 0, dataType = ""
    var headerCRC = 0, fileCRC = 0, headerCRCValid = false, fileCRCValid = false
    var messages: [FITMessage] = []
    func all(_ global: Int) -> [FITMessage] { messages.filter { $0.global == global } }
}
private func decodeFIT(_ data: Data) throws -> FITFile {
    let bytes = [UInt8](data)
    func le(_ at: Int, _ size: Int) -> UInt64 { (0..<size).reduce(0) { $0 | UInt64(bytes[at + $1]) << (8 * UInt64($1)) } }
    var file = FITFile()
    file.headerSize = Int(bytes[0]); file.protocolVersion = Int(bytes[1]); file.profileVersion = Int(le(2, 2))
    file.dataSize = Int(le(4, 4)); file.dataType = String(decoding: bytes[8..<12], as: UTF8.self)
    file.headerCRC = Int(le(12, 2)); file.fileCRC = Int(le(bytes.count - 2, 2))
    file.headerCRCValid = FITEncoder.crc16(bytes[0..<12]) == UInt16(file.headerCRC)
    file.fileCRCValid = FITEncoder.crc16(bytes[0..<(bytes.count - 2)]) == UInt16(file.fileCRC)
    var definitions: [Int: (global: Int, fields: [(num: Int, size: Int)])] = [:]
    var position = file.headerSize
    let end = file.headerSize + file.dataSize
    while position < end {
        let header = bytes[position]; position += 1
        let local = Int(header & 0x0F)
        if header & 0x40 != 0 {
            #expect(bytes[position + 1] == 0, "little endian") // architecture
            let global = Int(le(position + 2, 2)), count = Int(bytes[position + 4]); position += 5
            var fields: [(Int, Int)] = []
            for _ in 0..<count { fields.append((Int(bytes[position]), Int(bytes[position + 1]))); position += 3 }
            definitions[local] = (global, fields.map { (num: $0.0, size: $0.1) })
        } else {
            let definition = try #require(definitions[local])
            var values: [Int: UInt64] = [:], arrays: [Int: [UInt64]] = [:]
            for field in definition.fields {
                if field.size > 4 { arrays[field.num] = stride(from: 0, to: field.size, by: 2).map { le(position + $0, 2) } }
                let raw = le(position, field.size); position += field.size
                let invalid: UInt64 = field.size == 1 ? 0xFF : field.size == 2 ? 0xFFFF : 0xFFFF_FFFF
                if raw != invalid { values[field.num] = raw }
            }
            file.messages.append(FITMessage(global: definition.global, fields: values, arrays: arrays))
        }
    }
    #expect(position == end)
    return file
}

// MARK: Fixtures

private let start = Date(timeIntervalSince1970: 1_793_700_000)

private func configuration(prior: Double? = 250) throws -> SessionConfiguration {
    try SessionConfiguration(priorFTP: prior.map { FTPEntry(watts: $0) }, powerSource: .trainer, cadenceSource: .trainer)
}

private func rampSession() throws -> TestSession {
    var session = TestSession(startedAt: start, configuration: try configuration())
    for second in 0...360 {
        session.samples.append(RideSample(time: Double(second), power: Double(100 + second / 2), cadence: 90, heartRate: second < 10 ? nil : 120 + second / 10))
    }
    session.rampStart = 60; session.rampEnd = 300; session.endedAtOffset = 360; session.outcome = .exhaustion
    return session
}

private func pausedWorkout() throws -> TestSession {
    let plan = try TrainingPlan(kind: .workout, name: "Sweet spot", ftpWatts: 250, steps: [
        .init("Warm-up", seconds: 300, watts: 125), .init("Work", seconds: 300, watts: 225), .init("Cool-down", seconds: 300, watts: 125)])
    var session = TestSession(startedAt: start, configuration: try configuration())
    session.training = plan
    session.events = [SessionEvent(time: 5, message: "Training"),
                      SessionEvent(time: 400, message: "Training paused; trainer release requested"),
                      SessionEvent(time: 401, message: "Trainer release confirmed for pause"),
                      SessionEvent(time: 460, message: "Training resumed")]
    for second in 0...964 { session.samples.append(RideSample(time: Double(second), power: 150, cadence: 85)) }
    session.endedAtOffset = 964; session.outcome = .completed
    return session
}

// MARK: Tests

@Test func fitHeaderAndChecksumsAreValid() throws {
    let data = try ActivityExport.data(rampSession(), format: .fit)
    let file = try decodeFIT(data)
    #expect(file.headerSize == 14 && file.dataType == ".FIT")
    #expect(file.protocolVersion == 0x20 && file.profileVersion == 21221)
    #expect(file.dataSize == data.count - 14 - 2)
    #expect(file.headerCRCValid && file.fileCRCValid)
    // CRC-16/ARC check values.
    #expect(FITEncoder.crc16([UInt8]()) == 0)
    #expect(FITEncoder.crc16(Array("123456789".utf8)) == 0xBB3D) // the FIT CRC is CRC-16/ARC
}

@Test func fitRecordsRoundTripAndMissingValuesStayInvalid() throws {
    let session = try rampSession()
    let file = try decodeFIT(FITEncoder.fileData(session))
    let records = file.all(20)
    #expect(records.count == session.samples.count)
    let epoch = UInt64(start.timeIntervalSince1970 - FITEncoder.epochOffset)
    for (record, sample) in zip(records, session.samples) {
        #expect(record.fields[253] == epoch + UInt64(sample.time))
        #expect(record.fields[7] == UInt64(sample.power!.rounded()))
        #expect(record.fields[4] == 90)
        #expect(record.fields[3] == sample.heartRate.map { UInt64($0) })   // nil where the strap had no value; never 0
    }
    #expect(records[0].fields[3] == nil && records[20].fields[3] != nil)
}

@Test func fitMergesNotificationsOfTheSameSecondAndSkipsEmptyOnes() throws {
    var session = TestSession(startedAt: start, configuration: try configuration())
    session.samples = [RideSample(time: 1.1, power: 200), RideSample(time: 1.4, trainerPower: 210), RideSample(time: 1.6, cadence: 88),
                       RideSample(time: 1.9, heartRate: 140), RideSample(time: 2.5, trainerPower: 205), RideSample(time: 3.2, power: 220)]
    session.endedAtOffset = 4
    let records = try decodeFIT(FITEncoder.fileData(session)).all(20)
    #expect(records.count == 2)
    #expect(records[0].fields[7] == 200 && records[0].fields[4] == 88 && records[0].fields[3] == 140)
    #expect(records[1].fields[7] == 220 && records[1].fields[4] == nil)
}

@Test func fitLapsMatchTheTcxLapsOfARampTest() throws {
    let session = try rampSession()
    let file = try decodeFIT(FITEncoder.fileData(session))
    let laps = file.all(19)
    let epoch = UInt64(start.timeIntervalSince1970 - FITEncoder.epochOffset)
    #expect(laps.map { $0.fields[2] } == [epoch, epoch + 60, epoch + 300])
    #expect(laps.map { $0.fields[7] } == [60_000, 240_000, 60_000])
    let tcx = String(decoding: try ActivityExport.tcx(session), as: UTF8.self)
    #expect(tcx.components(separatedBy: "<Lap ").count - 1 == laps.count)
}

@Test func fitSessionTotalsExcludeTheTimeAWorkoutWasPaused() throws {
    let session = try pausedWorkout()
    let file = try decodeFIT(FITEncoder.fileData(session))
    let message = try #require(file.all(18).first)
    #expect(file.all(18).count == 1 && file.all(34).count == 1)
    #expect(message.fields[7] == 964_000)            // elapsed
    #expect(message.fields[8] == 905_000)            // timer: 59 s paused (release confirmed 401 -> resume 460)
    #expect(file.all(34).first?.fields[0] == 905_000 && file.all(34).first?.fields[1] == 1)
    // Timer events: start, stop at the confirmed release, start at resume, final stop.
    let timers = file.all(21).map { $0.fields[1] }
    #expect(timers == [0, 4, 0, 4])
    // Nothing is recorded while the timer was stopped.
    let epoch = UInt64(start.timeIntervalSince1970 - FITEncoder.epochOffset)
    let stamps = file.all(20).compactMap { $0.fields[253] }.map { $0 - epoch }
    #expect(!stamps.contains(where: { $0 >= 401 && $0 < 460 }) && stamps.contains(400) && stamps.contains(460))
    // One lap per step, the later ones shifted by the pause (step 2 ends at 5 + 600 s of riding + 59 s).
    let laps = file.all(19).map { $0.fields[2] ?? 0 }.map { $0 - epoch }
    #expect(laps == [0, 305, 664])
    let lapTimes: [UInt64?] = file.all(19).map { $0.fields[8] }
    let expectedLapTimes: [UInt64?] = [305_000, 300_000, 300_000]   // 359 000 - 59 000 = 300 000
    #expect(lapTimes == expectedLapTimes)
}

@Test func fitDescribesAnIndoorCyclingActivityWithTheRidersFTP() throws {
    let file = try decodeFIT(FITEncoder.fileData(rampSession()))
    let session = try #require(file.all(18).first)
    #expect(session.fields[5] == 2 && session.fields[6] == 6)       // cycling / indoor_cycling
    #expect(session.fields[45] == 250)                               // threshold power = prior FTP
    #expect(session.fields[26] == 3 && session.fields[20] != nil && session.fields[21] == 280)
    let id = try #require(file.all(0).first)
    #expect(id.fields[0] == 4 && id.fields[1] == 255)                // activity file, development manufacturer
    #expect(id.fields[3] != nil)
    #expect(file.all(34).first?.fields[2] == 0 && file.all(34).first?.fields[3] == 26)
    // No prior FTP: the field is invalid, not 0.
    var noFTP = try rampSession()
    noFTP.configuration = try configuration(prior: nil)
    #expect(try decodeFIT(FITEncoder.fileData(noFTP)).all(18).first?.fields[45] == nil)
    // Distance and speed are simulated from power: they grow along the records and the session and laps carry the same total.
    let distances = file.all(20).compactMap { $0.fields[5] }
    #expect(distances.count == file.all(20).count && distances == distances.sorted() && distances.last! > 0)
    #expect(file.all(20).allSatisfy { $0.fields[6] != nil })
    let total = try #require(session.fields[9])
    #expect(total == distances.last!)
    let laps = file.all(19).compactMap { $0.fields[9] }.reduce(0, +)
    #expect(laps >= total - 3 && laps <= total + 3)
    #expect(session.fields[48]! > 0 && session.fields[11]! > 0 && session.fields[14]! > 0 && session.fields[15]! >= session.fields[14]!)
    // Nothing reported balance in this session, so the fields stay invalid rather than 0.
    #expect(session.fields[37] == nil && file.all(20).allSatisfy { $0.fields[30] == nil })
}

@Test func fitRefusesUnfinishedAndEmptyActivities() throws {
    var session = try rampSession()
    session.endedAtOffset = nil
    #expect(throws: ExportError.notFinalized) { try FITEncoder.fileData(session) }
    var empty = TestSession(startedAt: start, configuration: try configuration()); empty.endedAtOffset = 10
    #expect(throws: ExportError.emptyActivity) { try FITEncoder.fileData(empty) }
    var silent = empty; silent.samples = [RideSample(time: 1)]
    #expect(throws: ExportError.emptyActivity) { try FITEncoder.fileData(silent) }
}

@Test func exportFileNamesAreSafeAndMarkDebugRides() throws {
    var session = try rampSession()
    session.startedAt = Date(timeIntervalSince1970: 1_793_700_000)
    let name = ActivityExport.fileName(session, format: .fit)
    #expect(name.hasPrefix("FTPunk-20") && name.hasSuffix(".fit"))
    #expect(name.dropLast(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    session.isDemo = true
    #expect(ActivityExport.fileName(session, format: .tcx).hasPrefix("DEMO-FTPunk-"))
    var workout = try pausedWorkout()
    workout.training = try TrainingPlan(kind: .workout, name: "Über/Under: 3×9 min!", steps: [.init("a", seconds: 60, watts: 100)])
    #expect(ActivityExport.fileName(workout, format: .csv).hasSuffix("-ber-Under-3-9-min.csv"))
}

@Test func everyFormatExportsThroughOneEntryPoint() throws {
    let session = try rampSession()
    for format in ActivityFileFormat.allCases { #expect(try !ActivityExport.data(session, format: format).isEmpty) }
}

/// Writes the fixtures to FTPUNK_FIT_DUMP_DIR so an independent decoder (fitdecode, fitparse) can be run over them by hand.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FTPUNK_FIT_DUMP_DIR"] != nil))
func dumpFitFixturesForExternalDecoders() throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["FTPUNK_FIT_DUMP_DIR"]))
    try FITEncoder.fileData(rampSession()).write(to: directory.appendingPathComponent("ramp.fit"))
    try FITEncoder.fileData(pausedWorkout()).write(to: directory.appendingPathComponent("workout-paused.fit"))
}

// MARK: Training load and RR intervals

private func steadySession(ftp: Double? = 200, seconds: Int) throws -> TestSession {
    var session = TestSession(startedAt: start, configuration: try configuration(prior: ftp))
    session.samples = (0..<seconds).map { RideSample(time: Double($0), power: 200) }
    session.endedAtOffset = Double(seconds)
    return session
}

@Test func fitSessionCarriesNormalizedPowerStressAndIntensity() throws {
    let file = try decodeFIT(try FITEncoder.fileData(try steadySession(seconds: 3600)))
    let session = try #require(file.all(18).first), lap = try #require(file.all(19).first)
    #expect(session.fields[34] == 200); #expect(session.fields[35] == 1000); #expect(session.fields[36] == 1000); #expect(lap.fields[33] == 200)
}

@Test func fitLoadFieldsAreInvalidWithoutFTPOrThirtySeconds() throws {
    let noFTP = try #require(try decodeFIT(try FITEncoder.fileData(try steadySession(ftp: nil, seconds: 600))).all(18).first)
    #expect(noFTP.fields[34] == 200); #expect(noFTP.fields[35] == nil); #expect(noFTP.fields[36] == nil)
    let short = try decodeFIT(try FITEncoder.fileData(try steadySession(seconds: 20)))
    let shortSession = try #require(short.all(18).first)
    #expect(shortSession.fields[34] == nil); #expect(shortSession.fields[35] == nil); #expect(shortSession.fields[36] == nil)
    #expect(short.all(19).first?.fields[33] == nil)
}

@Test func fitLapPowerUsesOnlyThatLapsUnpausedSamples() throws {
    var session = try steadySession(seconds: 200)
    session.rampStart = 20 // the first lap is too short for a normalized power
    session.samples = session.samples.map { $0.time >= 100 && $0.time < 140 ? RideSample(time: $0.time, power: 900) : $0 }
    session.events = [SessionEvent(time: 100, message: "Training paused; trainer release requested"), SessionEvent(time: 140, message: "Training resumed")]
    let laps = try decodeFIT(try FITEncoder.fileData(session)).all(19)
    #expect(laps.count == 2); #expect(laps[0].fields[33] == nil); #expect(laps[1].fields[33] == 200)
}

@Test func hrvValuesAreSplitAndPaddedToFixedMessages() {
    let invalid: UInt64 = 0xFFFF
    #expect(FITEncoder.hrvMessages([]).isEmpty)
    #expect(FITEncoder.hrvMessages([1]) == [[1, invalid, invalid, invalid, invalid]])
    #expect(FITEncoder.hrvMessages([1, 2, 3, 4, 5]) == [[1, 2, 3, 4, 5]])
    #expect(FITEncoder.hrvMessages([1, 2, 3, 4, 5, 6]) == [[1, 2, 3, 4, 5], [6, invalid, invalid, invalid, invalid]])
}

@Test func hrvMessagesFollowTheirRecordAndSkipPausesAndEmptySeconds() throws {
    var session = TestSession(startedAt: start, configuration: try configuration())
    session.samples = [
        RideSample(time: 1, power: 100, heartRate: 120, rrIntervals: [0.5]),
        RideSample(time: 2, power: 100, heartRate: 120, rrIntervals: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]),
        RideSample(time: 3.6, heartRate: 120, rrIntervals: [0.4]),
        RideSample(time: 3.2, power: 100, rrIntervals: [0.3]), // out of order: time decides
        RideSample(time: 4, rrIntervals: [0.9]), // RR but no record for this second
        RideSample(time: 5.5, power: 100, heartRate: 120, rrIntervals: [0.8]), // paused
        RideSample(time: 6, power: 100, heartRate: 120, rrIntervals: [70, .nan, 0]), // capped, unusable values dropped
        RideSample(time: 7, power: 100, heartRate: 120)]
    session.events = [SessionEvent(time: 5, message: "Training paused; trainer release requested"), SessionEvent(time: 6, message: "Training resumed")]
    session.endedAtOffset = 8
    let file = try decodeFIT(try FITEncoder.fileData(session)), none: UInt64 = 0xFFFF
    let expected: [[UInt64]] = [
        [500, none, none, none, none], [100, 200, 300, 400, 500], [600, 700, none, none, none], [300, 400, none, none, none], [65534, none, none, none, none]]
    let written: [[UInt64]] = file.all(78).map { $0.arrays[0] ?? [] }
    #expect(written == expected)
    for (index, message) in file.messages.enumerated() where message.global == 78 {
        #expect(file.messages[index - 1].global == 20 || file.messages[index - 1].global == 78)
    }
    #expect(file.all(20).count == 5) // seconds 1, 2, 3, 6 and 7
}
