import FTPunkDomain

/// One rider-facing choice that maps onto `AppModel.powerSource` + `powerMatchingEnabled`.
enum PowerMode: String, CaseIterable, Identifiable {
    case trainer, meterMatched, meterRecordOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .trainer: "Trainer"
        case .meterMatched: "Power meter — trainer follows the meter"
        case .meterRecordOnly: "Power meter — record only, no matching"
        }
    }

    /// The mode a stored (source, matching) pair represents. Without a connected meter the answer is always `.trainer`.
    static func resolve(powerSource: PowerSource, matchingEnabled: Bool, meterConnected: Bool) -> PowerMode {
        guard meterConnected, powerSource == .externalPowerMeter else { return .trainer }
        return matchingEnabled ? .meterMatched : .meterRecordOnly
    }

    /// The model values for this mode. `.trainer` keeps the stored matching preference for the next time a meter is used.
    func settings(currentMatching: Bool) -> (powerSource: PowerSource, matchingEnabled: Bool) {
        switch self {
        case .trainer: (.trainer, currentMatching)
        case .meterMatched: (.externalPowerMeter, true)
        case .meterRecordOnly: (.externalPowerMeter, false)
        }
    }
}
