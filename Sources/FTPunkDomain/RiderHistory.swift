import Foundation

public struct RiderHistoryGroup: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let sessions: [TestSession]
}

public enum RiderHistory {
    /// Identity, rather than a display name, keeps different riders' results separate.
    public static func groups(sessions: [TestSession], profiles: [RiderProfile]) -> [RiderHistoryGroup] {
        Dictionary(grouping: sessions, by: \.riderID).map { id, tests in
            RiderHistoryGroup(id: id, name: profiles.first(where: { $0.id == id })?.name ?? tests[0].riderName,
                              sessions: tests.sorted { $0.startedAt > $1.startedAt })
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }
}
