import Foundation

/// Whether a finished activity should open the upload consent sheet by itself. The prompt only ever asks; it never uploads.
public enum UploadPromptRule {
    /// A workout, free ERG or resistance ride shorter than this is not worth a prompt. The manual button still works.
    public static let minimumRideSeconds = 300.0

    public static func shouldAsk(session: TestSession, hasConnection: Bool, askEnabled: Bool, existingJob: ActivityUploadJob?) -> Bool {
        guard hasConnection, askEnabled, existingJob == nil, !session.isDemo, let ended = session.endedAtOffset else { return false }
        if session.training == nil { return session.result != nil && session.outcome?.allowsEstimate == true }
        switch session.outcome {
        case .completed, .aborted: return ended >= minimumRideSeconds
        default: return false // interrupted rides (lost trainer, crash recovery) are never prompted
        }
    }
}
