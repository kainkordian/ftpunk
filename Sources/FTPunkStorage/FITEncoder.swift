import Foundation
import FTPunkDomain

/// A minimal FIT *activity* file writer (no dependencies). Field numbers and base types were checked against the
/// FIT SDK profile 21.221 (garmin/fit-javascript-sdk `profile.js`) on 2026-11-04:
///
///     file_id(0):  type 0 enum, manufacturer 1 uint16, product 2 uint16, serial_number 3 uint32z, time_created 4 uint32
///     event(21):   timestamp 253, event 0 enum (timer = 0), event_type 1 enum (start = 0, stop_all = 4)
///     record(20):  timestamp 253, heart_rate 3 uint8, cadence 4 uint8, power 7 uint16, distance 5 uint32 (cm), speed 6 uint16 (mm/s),
///                  left_right_balance 30 uint8 (percent, 0x80 = the value is the right leg's)
///     lap(19):     timestamp 253, event 0, event_type 1, start_time 2, total_elapsed_time 7 (ms), total_timer_time 8 (ms),
///                  sport 25, sub_sport 39, message_index 254, total_distance 9, total_calories 11, avg_speed 13, max_speed 14, total_work 41
///     session(18): timestamp 253, event 0, event_type 1, start_time 2, sport 5, sub_sport 6, total_elapsed_time 7, total_timer_time 8,
///                  avg_heart_rate 16, max_heart_rate 17, avg_cadence 18, max_cadence 19, avg_power 20, max_power 21,
///                  first_lap_index 25, num_laps 26, threshold_power 45, message_index 254, total_distance 9, total_calories 11, avg_speed 14,
///                  max_speed 15, left_right_balance 37 uint16 (percent × 100, 0x8000 = right leg), total_work 48 (J)
///
/// Distance and speed are simulated from power (`RideTrack`); checked against profile 21.221 on 2026-11-09.
///     Added 2026-11-09: session normalized_power 34 uint16, training_stress_score 35 uint16 (× 10), intensity_factor 36 uint16 (× 1000); lap normalized_power 33;
///     hrv(78): time 0 uint16 array (ms), a fixed five elements per message padded with the invalid value.
///     activity(34): timestamp 253, total_timer_time 0 (ms), num_sessions 1, type 2 (manual = 0), event 3 (activity = 26),
///                  event_type 4 (stop = 1), local_timestamp 5
///
/// Enum values: file type activity = 4, manufacturer development = 255, sport cycling = 2, sub-sport indoor_cycling = 6,
/// event session = 8, lap = 9.
public enum FITEncoder {
    public static let profileVersion: UInt16 = 21221
    public static let epochOffset: TimeInterval = 631_065_600 // Unix seconds at 1989-12-31 00:00:00 UTC

    // MARK: Bytes

    struct BaseType {
        let id: UInt8, size: UInt8, invalid: UInt64
        static let enumeration = BaseType(id: 0x00, size: 1, invalid: 0xFF)
        static let uint8 = BaseType(id: 0x02, size: 1, invalid: 0xFF)
        static let uint16 = BaseType(id: 0x84, size: 2, invalid: 0xFFFF)
        static let uint32 = BaseType(id: 0x86, size: 4, invalid: 0xFFFF_FFFF)
        static let uint32z = BaseType(id: 0x8C, size: 4, invalid: 0)
    }
    /// One value, or with `array` a fixed-length array (the definition's size is the element size × its count).
    struct Field { let number: UInt8, type: BaseType, value: UInt64?; var array: [UInt64]? = nil }
    static let hrvArrayLength = 5

    /// The FIT SDK's CRC-16 (nibble table).
    public static func crc16(_ bytes: some Sequence<UInt8>, seed: UInt16 = 0) -> UInt16 {
        let table: [UInt16] = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]
        var crc = seed
        for byte in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }

    private struct Writer {
        var data = Data()
        private var defined: Set<UInt8> = []
        mutating func message(local: UInt8, global: UInt16, _ fields: [Field]) {
            if !defined.contains(local) {
                defined.insert(local)
                data.append(0x40 | local); data.append(0); data.append(0) // definition header, reserved, little endian
                data.append(contentsOf: little(UInt64(global), 2)); data.append(UInt8(fields.count))
                for field in fields { data.append(field.number); data.append(field.type.size * UInt8(field.array?.count ?? 1)); data.append(field.type.id) }
            }
            data.append(local)
            for field in fields {
                if let values = field.array {
                    for value in values { data.append(contentsOf: little(value, Int(field.type.size))) }
                } else {
                    data.append(contentsOf: little(field.value ?? field.type.invalid, Int(field.type.size)))
                }
            }
        }
        private func little(_ value: UInt64, _ size: Int) -> [UInt8] { (0..<size).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) } }
    }

    // MARK: Session model

    typealias Pause = RidePause
    static func pauses(_ session: TestSession) -> [Pause] { RidePause.list(session) }

    /// Where the laps start, as offsets from the start of the recording. Tests use the TCX boundaries (warm-up, ramp,
    /// cool-down). A workout gets one lap per step when it has at most 100 steps, mapped through its pauses.
    static func lapStarts(_ session: TestSession, end: Double, pauses: [Pause]) -> [Double] {
        if let plan = session.training, plan.kind == .workout, plan.steps.count > 1, plan.steps.count <= 100,
           let begin = session.events.first(where: { $0.message == WorkoutPhase.riding.title })?.time {
            var starts = [0.0], active = 0.0
            for step in plan.steps.dropLast() {
                active += step.seconds
                var wall = begin + active
                for pause in pauses.sorted(by: { $0.stop < $1.stop }) where pause.stop <= wall { wall += (pause.resume ?? end) - pause.stop }
                if wall > (starts.last ?? 0), wall < end { starts.append(wall) }
            }
            return starts
        }
        return ActivityExport.phaseBoundaries(session, end: end).dropLast()
    }

    private struct Merged { var time: Int; var heartRate: Int?, cadence: Int?, power: Int? }

    /// One record per second: Bluetooth notifications from the meter, the trainer and the strap arrive separately, and the
    /// latest real value of each field in that second is kept. Seconds with no value at all, and paused time, are left out.
    private static func merge(_ samples: [RideSample], pauses: [Pause], end: Double) -> [Merged] {
        var records: [Int: Merged] = [:]
        for sample in samples where sample.time.isFinite && sample.time >= 0 && sample.time <= end {
            if pauses.contains(where: { sample.time >= $0.stop && sample.time < ($0.resume ?? .infinity) }) { continue }
            let second = Int(sample.time.rounded(.down))
            var value = records[second] ?? Merged(time: second)
            if let hr = sample.heartRate { value.heartRate = min(254, max(0, hr)) }
            if let cadence = sample.cadence, cadence.isFinite { value.cadence = Int(min(254, max(0, cadence.rounded()))) }
            if let power = sample.power, power.isFinite { value.power = Int(min(65534, max(0, power.rounded()))) }
            records[second] = value
        }
        return records.values.filter { $0.heartRate != nil || $0.cadence != nil || $0.power != nil }.sorted { $0.time < $1.time }
    }

    /// RR intervals in milliseconds per second of the ride, in time order. Paused and out-of-range samples and unusable values are left out.
    private static func rrBySecond(_ samples: [RideSample], pauses: [Pause], end: Double) -> [Int: [UInt64]] {
        let ordered = samples.enumerated().filter { entry in
            let time = entry.element.time
            return entry.element.rrIntervals != nil && time.isFinite && time >= 0 && time <= end && !pauses.contains { $0.contains(time) }
        }.sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
        var result: [Int: [UInt64]] = [:]
        for entry in ordered {
            let second = Int(entry.element.time.rounded(.down))
            for rr in entry.element.rrIntervals ?? [] where rr.isFinite && rr > 0 {
                result[second, default: []].append(UInt64(min(65534, (rr * 1000).rounded())))
            }
        }
        return result
    }

    /// Splits RR values over `hrv` messages of a fixed length, padding the last one with uint16's invalid value.
    static func hrvMessages(_ values: [UInt64]) -> [[UInt64]] {
        stride(from: 0, to: values.count, by: hrvArrayLength).map { first in
            let part = Array(values[first..<min(first + hrvArrayLength, values.count)])
            return part + Array(repeating: BaseType.uint16.invalid, count: hrvArrayLength - part.count)
        }
    }

    public static func fileData(_ session: TestSession) throws -> Data {
        guard let end = session.endedAtOffset else { throw ExportError.notFinalized }
        guard !session.samples.isEmpty else { throw ExportError.emptyActivity }
        let pauses = pauses(session)
        let records = merge(session.samples, pauses: pauses, end: end)
        guard !records.isEmpty else { throw ExportError.emptyActivity }

        func fit(_ offset: Double) -> UInt64 {
            UInt64(max(0, (session.startedAt.timeIntervalSince1970 + offset - epochOffset).rounded(.down)))
        }
        func ms(_ seconds: Double) -> UInt64 { UInt64(max(0, (seconds * 1000).rounded())) }
        func u(_ value: Int?) -> UInt64? { value.map { UInt64(max(0, $0)) } }
        func capped(_ value: Double, _ limit: UInt64) -> UInt64 { UInt64(min(Double(limit), max(0, value.rounded()))) }

        let track = RideTrack.make(samples: session.samples, pauses: pauses, end: end, riderKG: session.configuration.weightKG)
        let trackBySecond = Dictionary(uniqueKeysWithValues: track.points.map { ($0.second, $0) })
        let balance = RideBalance.make(samples: session.samples, pauses: pauses, end: end, track: track)
        let leftBySecond = Dictionary(uniqueKeysWithValues: (balance?.seconds ?? []).map { ($0.second, $0.left) })
        var covered: Double?
        let load = TrainingLoad.make(session, track: track)
        let rrIntervals = rrBySecond(session.samples, pauses: pauses, end: end)

        let pausedSeconds = pauses.reduce(0.0) { $0 + min(end, $1.resume ?? end) - min(end, $1.stop) }
        let timerSeconds = max(0, end - pausedSeconds)
        let startTime = fit(0), endTime = fit(end)

        var writer = Writer()
        let uuid = session.id.uuid, serial = UInt64(uuid.0) << 24 | UInt64(uuid.1) << 16 | UInt64(uuid.2) << 8 | UInt64(uuid.3)
        writer.message(local: 0, global: 0, [
            Field(number: 0, type: .enumeration, value: 4), Field(number: 1, type: .uint16, value: 255), Field(number: 2, type: .uint16, value: 1),
            Field(number: 3, type: .uint32z, value: max(1, serial & 0xFFFF_FFFF)), Field(number: 4, type: .uint32, value: startTime)])

        func timer(_ type: UInt64, at offset: Double) {
            writer.message(local: 1, global: 21, [Field(number: 253, type: .uint32, value: fit(offset)),
                                                  Field(number: 0, type: .enumeration, value: 0), Field(number: 1, type: .enumeration, value: type)])
        }
        // Records and timer events in time order: start, [stop, start]…, records, final stop.
        enum Item { case record(Merged), stop(Double), start(Double) }
        var items: [(time: Double, order: Int, item: Item)] = records.map { (Double($0.time), 1, .record($0)) }
        for pause in pauses {
            items.append((pause.stop, 0, .stop(pause.stop)))
            if let resume = pause.resume, resume < end { items.append((resume, 0, .start(resume))) }
        }
        items.sort { ($0.time, $0.order) < ($1.time, $1.order) }
        timer(0, at: Double(records[0].time))
        for entry in items {
            switch entry.item {
            case .stop(let at): timer(4, at: at)
            case .start(let at): timer(0, at: at)
            case .record(let record):
                let point = trackBySecond[record.time]
                if let point { covered = point.distance }
                writer.message(local: 2, global: 20, [
                    Field(number: 253, type: .uint32, value: fit(Double(record.time))), Field(number: 3, type: .uint8, value: u(record.heartRate)),
                    Field(number: 4, type: .uint8, value: u(record.cadence)), Field(number: 7, type: .uint16, value: u(record.power)),
                    Field(number: 5, type: .uint32, value: covered.map { capped($0 * 100, 4_294_967_294) }),
                    Field(number: 6, type: .uint16, value: point.map { capped($0.speed * 1000, 65534) }),
                    Field(number: 30, type: .uint8, value: leftBySecond[record.time].map { 0x80 | capped(100 - $0, 100) })])
                for values in hrvMessages(rrIntervals[record.time] ?? []) {
                    writer.message(local: 6, global: 78, [Field(number: 0, type: .uint16, value: nil, array: values)])
                }
            }
        }
        if !(pauses.last.map { $0.resume == nil } ?? false) { timer(4, at: end) }

        let starts = lapStarts(session, end: end, pauses: pauses)
        for (index, begin) in starts.enumerated() {
            let finish = index + 1 < starts.count ? starts[index + 1] : end
            let paused = pauses.reduce(0.0) { $0 + max(0, min(finish, $1.resume ?? end) - max(begin, $1.stop)) }
            let lap = track.span(from: begin, to: index + 1 < starts.count ? finish : .infinity), lapRidden = lap.seconds > 0
            let isLast = index + 1 == starts.count
            let lapSamples = session.samples.filter { $0.time >= begin && (isLast ? $0.time <= end : $0.time < finish) }
            let lapPower = RideSummary.normalizedPower(lapSamples, pauses: pauses)
            writer.message(local: 3, global: 19, [
                Field(number: 254, type: .uint16, value: UInt64(index)), Field(number: 253, type: .uint32, value: fit(finish)),
                Field(number: 0, type: .enumeration, value: 9), Field(number: 1, type: .enumeration, value: 1),
                Field(number: 2, type: .uint32, value: fit(begin)), Field(number: 7, type: .uint32, value: ms(finish - begin)),
                Field(number: 8, type: .uint32, value: ms(max(0, finish - begin - paused))),
                Field(number: 25, type: .enumeration, value: 2), Field(number: 39, type: .enumeration, value: 6),
                Field(number: 9, type: .uint32, value: lapRidden ? capped(lap.distance * 100, 4_294_967_294) : nil),
                Field(number: 11, type: .uint16, value: lapRidden ? capped(lap.kilocalories, 65534) : nil),
                Field(number: 13, type: .uint16, value: lapRidden ? capped(lap.averageSpeed * 1000, 65534) : nil),
                Field(number: 14, type: .uint16, value: lapRidden ? capped(lap.maximumSpeed * 1000, 65534) : nil),
                Field(number: 41, type: .uint32, value: lapRidden ? capped(lap.joules, 4_294_967_294) : nil),
                Field(number: 33, type: .uint16, value: lapPower.map { capped($0, 65534) })])
        }

        func stats(_ values: [Int]) -> (average: Int, maximum: Int)? {
            values.isEmpty ? nil : (Int((Double(values.reduce(0, +)) / Double(values.count)).rounded()), values.max() ?? 0)
        }
        let power = stats(records.compactMap(\.power)), heart = stats(records.compactMap(\.heartRate)), cadence = stats(records.compactMap(\.cadence))
        let whole = track.whole, ridden = whole.seconds > 0
        writer.message(local: 4, global: 18, [
            Field(number: 254, type: .uint16, value: 0), Field(number: 253, type: .uint32, value: endTime),
            Field(number: 0, type: .enumeration, value: 8), Field(number: 1, type: .enumeration, value: 1),
            Field(number: 2, type: .uint32, value: startTime), Field(number: 5, type: .enumeration, value: 2), Field(number: 6, type: .enumeration, value: 6),
            Field(number: 7, type: .uint32, value: ms(end)), Field(number: 8, type: .uint32, value: ms(timerSeconds)),
            Field(number: 16, type: .uint8, value: u(heart?.average)), Field(number: 17, type: .uint8, value: u(heart?.maximum)),
            Field(number: 18, type: .uint8, value: u(cadence?.average)), Field(number: 19, type: .uint8, value: u(cadence?.maximum)),
            Field(number: 20, type: .uint16, value: u(power?.average)), Field(number: 21, type: .uint16, value: u(power?.maximum)),
            Field(number: 25, type: .uint16, value: 0), Field(number: 26, type: .uint16, value: UInt64(starts.count)),
            Field(number: 45, type: .uint16, value: session.configuration.priorFTP.map { UInt64(min(65534, max(0, $0.watts.rounded()))) }),
            Field(number: 9, type: .uint32, value: ridden ? capped(whole.distance * 100, 4_294_967_294) : nil),
            Field(number: 11, type: .uint16, value: ridden ? capped(whole.kilocalories, 65534) : nil),
            Field(number: 14, type: .uint16, value: ridden ? capped(whole.averageSpeed * 1000, 65534) : nil),
            Field(number: 15, type: .uint16, value: ridden ? capped(whole.maximumSpeed * 1000, 65534) : nil),
            Field(number: 37, type: .uint16, value: balance.map { 0x8000 | capped((100 - $0.left) * 100, 10000) }),
            Field(number: 48, type: .uint32, value: ridden ? capped(whole.joules, 4_294_967_294) : nil),
            Field(number: 34, type: .uint16, value: load.normalizedPower.map { capped($0, 65534) }),
            Field(number: 35, type: .uint16, value: load.trainingStressScore.map { capped($0 * 10, 65534) }),
            Field(number: 36, type: .uint16, value: load.intensityFactor.map { capped($0 * 1000, 65534) })])

        let zone = TimeInterval(TimeZone.current.secondsFromGMT(for: session.startedAt.addingTimeInterval(end)))
        writer.message(local: 5, global: 34, [
            Field(number: 253, type: .uint32, value: endTime), Field(number: 0, type: .uint32, value: ms(timerSeconds)),
            Field(number: 1, type: .uint16, value: 1), Field(number: 2, type: .enumeration, value: 0),
            Field(number: 3, type: .enumeration, value: 26), Field(number: 4, type: .enumeration, value: 1),
            Field(number: 5, type: .uint32, value: UInt64(max(0, Double(endTime) + zone)))])

        var header = Data([14, 0x20, UInt8(profileVersion & 0xFF), UInt8(profileVersion >> 8)])
        let size = UInt32(writer.data.count)
        header.append(contentsOf: (0..<4).map { UInt8((size >> (8 * UInt32($0))) & 0xFF) })
        header.append(contentsOf: Array(".FIT".utf8))
        let headerCRC = crc16(header)
        header.append(UInt8(headerCRC & 0xFF)); header.append(UInt8(headerCRC >> 8))
        var file = header + writer.data
        let fileCRC = crc16(file)
        file.append(UInt8(fileCRC & 0xFF)); file.append(UInt8(fileCRC >> 8))
        return file
    }
}
