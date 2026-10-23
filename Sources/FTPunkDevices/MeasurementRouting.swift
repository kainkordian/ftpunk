import Foundation
import FTPunkDomain

extension PowerSource {
    public var deviceRole: DeviceRole { self == .trainer ? .trainer : .pedals }
}

extension CadenceSource {
    public var deviceRole: DeviceRole? {
        switch self { case .trainer: .trainer; case .externalPowerMeter: .pedals; case .unavailable: nil }
    }
}

/// Keep field timestamps independently: an unrelated notification cannot refresh power or cadence.
public struct DeviceMeasurements: Sendable {
    private struct Value: Sendable { let time: Double; let value: Double }
    private var power: [DeviceRole: Value] = [:]
    private var cadence: [DeviceRole: Value] = [:]
    public init() {}
    public mutating func receive(_ reading: DeviceReading) {
        guard reading.uptime.isFinite else { return }
        if let watts = reading.power, watts.isFinite {
            power[reading.role] = Value(time: reading.uptime, value: watts)
        }
        if let rpm = reading.cadence, rpm.isFinite, rpm >= 0 {
            cadence[reading.role] = Value(time: reading.uptime, value: rpm)
        }
    }
    public mutating func reset(_ role: DeviceRole) { power[role] = nil; cadence[role] = nil }
    public func hasFreshPower(from source: PowerSource, at time: Double) -> Bool {
        fresh(power[source.deviceRole], at: time) != nil
    }
    public func preferredCadence(for source: PowerSource, at time: Double) -> CadenceSource {
        if source == .externalPowerMeter, fresh(cadence[.pedals], at: time) != nil { return .externalPowerMeter }
        return fresh(cadence[.trainer], at: time) != nil ? .trainer : .unavailable
    }
    private func fresh(_ value: Value?, at time: Double) -> Double? {
        guard let value, time >= value.time, time - value.time <= 2 else { return nil }
        return value.value
    }
}

public enum MeasurementRouting {
    /// Sources are fixed by the session snapshot. A disconnect never silently changes the scored stream.
    public static func sample(_ reading: DeviceReading, configuration: SessionConfiguration, origin: Double) -> RideSample? {
        let time = reading.uptime - origin
        guard time.isFinite, time >= 0 else { return nil }
        return RideSample(time: time,
                          power: reading.role == configuration.resolvedPowerSource.deviceRole ? reading.power : nil,
                          cadence: reading.role == configuration.resolvedCadenceSource.deviceRole ? reading.cadence : nil,
                          heartRate: reading.heartRate,
                          trainerPower: reading.role == .trainer ? reading.power : nil)
    }
    public static func isEssential(_ role: DeviceRole, configuration: SessionConfiguration) -> Bool {
        role == .trainer || role == configuration.resolvedPowerSource.deviceRole || role == configuration.resolvedCadenceSource.deviceRole
    }
}
