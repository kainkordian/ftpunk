import Foundation

public enum MockScenario: String, CaseIterable, Identifiable, Sendable {
    case rampToExhaustion, steadyRider, powerDropout, cadenceDropout
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rampToExhaustion: "Ramp to exhaustion"
        case .steadyRider: "Steady rider"
        case .powerDropout: "Power signal lost"
        case .cadenceDropout: "Cadence signal lost"
        }
    }
}

/// Repeatable device-free input. Missing fields represent lost signals, not zero.
public struct MockRideStream: Sendable {
    private var lastTime: Double?
    private var measuredPower: Double = 100
    public init() {}

    public mutating func sample(at time: Double, target: Int, phase: WorkoutPhase,
                                scenario: MockScenario = .rampToExhaustion,
                                powerSource: PowerSource = .trainer,
                                manualPower: Double? = nil, manualCadence: Double? = nil,
                                manualHeartRate: Int? = nil) -> RideSample {
        let delta = max(0, min(1, time - (lastTime ?? time)))
        lastTime = time
        let exhausted = scenario == .rampToExhaustion && phase == .ramp && target > 300
        let cadence = manualCadence ?? (exhausted ? 28 : 88 + 3 * sin(time / 7))
        let desired = manualPower ?? (cadence < 10 ? 0 : Double(target) * (exhausted ? 0.4 : 1))
        measuredPower += (desired - measuredPower) * (1 - exp(-delta / 0.8))
        let power = manualPower ?? max(0, measuredPower + (cadence < 10 ? 0 : 2 * sin(time / 3)))
        let hr = manualHeartRate ?? Int(min(190, 100 + Double(target) * 0.2 + 2 * sin(time / 11)))
        return RideSample(time: time, power: scenario == .powerDropout ? nil : power,
                          cadence: scenario == .cadenceDropout ? nil : cadence,
                          heartRate: hr, trainerPower: powerSource == .trainer ? (scenario == .powerDropout ? nil : power) : max(0, Double(target) * 0.98),
                          leftBalance: scenario == .powerDropout ? nil : 49 + 1.5 * sin(time / 29),
                          rrIntervals: hr > 0 ? [60.0 / Double(hr)] : nil)
    }
}
