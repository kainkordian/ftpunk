import Foundation

/// Calendar-only admission rule. Inspect the original targets, before resolved watts erase their units.
/// File imports and the workout builder deliberately do not use this rule.
public enum CalendarWorkoutPolicy {
    public static func qualifies(_ event: [String: Any]) -> Bool {
        guard let sport = event["type"] as? String, ["Ride", "VirtualRide"].contains(sport),
              let document = event["workout_doc"] as? [String: Any],
              let steps = document["steps"] as? [[String: Any]] else { return false }
        return containsPercentPower(steps)
    }

    private static func containsPercentPower(_ steps: [[String: Any]]) -> Bool {
        // Iteration also handles invalid/deep repeats: qualifying malformed workouts reach the decoder
        // and get a named error rather than silently disappearing.
        var pending = steps
        while let step = pending.popLast() {
            if let children = step["steps"] as? [[String: Any]] {
                pending.append(contentsOf: children)
            } else if let power = step["power"] as? [String: Any],
                      (power["units"] as? String)?.lowercased() == "%ftp" {
                return true
            }
        }
        return false
    }

    public static func syncSummary(count: Int) -> String {
        "\(count) cycling workouts with % FTP targets synced"
    }
}
