import Foundation
import FTPunkDomain
import FTPunkIntegrations

/// Per-rider Intervals.icu state: the connection, FTP and weight sync, and the upload prompt choice.
/// Pure rules live in `AthleteSync` and `UploadPromptRule`.
extension AppModel {
    static let promptDisabledKey = "intervalsPromptDisabledRiders"
    func syncKey(_ riderID: UUID) -> String { "intervalsAthleteSync.rider.\(riderID.uuidString.lowercased())" }

    /// Loads the selected rider's stored sync choices.
    func loadAthleteSync() {
        guard connection != nil else { athleteSync = AthleteSyncSettings(); return }
        athleteSync = (preview ? nil : UserDefaults.standard.data(forKey: syncKey(profile.id))
            .flatMap { try? JSONDecoder().decode(AthleteSyncSettings.self, from: $0) }) ?? AthleteSyncSettings()
        saveAthleteSync()
    }
    private func saveAthleteSync() {
        guard !preview, connection != nil, let data = try? JSONEncoder().encode(athleteSync) else { return }
        UserDefaults.standard.set(data, forKey: syncKey(profile.id))
    }

    func setAthleteSyncEnabled(_ enabled: Bool) {
        athleteSync.enabled = enabled; saveAthleteSync()
        if enabled { Task { await syncAthleteSettings(manual: true) } } else { athleteSyncNote = nil }
    }

    /// "Ask to upload after each ride", per rider, on by default.
    var askToUploadAfterRide: Bool {
        get { !uploadPromptDisabled.contains(profile.id) }
        set {
            if newValue { uploadPromptDisabled.remove(profile.id) } else { uploadPromptDisabled.insert(profile.id) }
            if !preview { UserDefaults.standard.set(uploadPromptDisabled.map(\.uuidString).sorted(), forKey: Self.promptDisabledKey) }
        }
    }

    /// Once, on launch: the app-wide connection of earlier versions moves to the rider the athlete sync was linked to
    /// (fallback: the selected rider), together with that account's sync settings. Safe to repeat.
    func migrateLegacyConnection() throws {
        guard let legacy = try credentials.loadLegacy() else { return }
        let oldKey = "intervalsAthleteSync.\(legacy.athleteID)"
        let stored = preview ? nil : UserDefaults.standard.data(forKey: oldKey).flatMap { try? JSONDecoder().decode(AthleteSyncSettings.self, from: $0) }
        let target = AthleteSync.linkedRiderID(stored: stored?.linkedRiderID, riders: riders, selected: profile.id)
        try credentials.migrateLegacyConnection(to: target)
        guard !preview else { return }
        if var settings = stored, UserDefaults.standard.data(forKey: syncKey(target)) == nil {
            settings.linkedRiderID = nil
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: syncKey(target)) }
        }
        UserDefaults.standard.removeObject(forKey: oldKey)
    }

    /// Reads every rider's connection. A credential whose rider no longer exists (a restore removed them) is deleted
    /// together with that account's pending uploads.
    func loadConnections() throws {
        for id in try credentials.allRiderIDs() where !riders.contains(where: { $0.id == id }) {
            if let orphan = try credentials.load(riderID: id) { try store.deleteUploadJobs(accountID: orphan.athleteID) }
            try credentials.clear(riderID: id)
            if !preview { UserDefaults.standard.removeObject(forKey: syncKey(id)) }
        }
        var loaded: [UUID: IntervalsConnection] = [:]
        for rider in riders { if let value = try credentials.load(riderID: rider.id) { loaded[rider.id] = value } }
        connections = loaded
    }

    /// Downloads the athlete record and applies changed values. Never during a ride; failures never break the connection.
    func syncAthleteSettings(manual: Bool = false) async {
        guard let connection, !preview, !isBusy, !athleteSyncing, athleteSync.enabled else { return }
        guard connection.canReadAthleteSettings else { athleteSyncNeedsReconnect = true; return }
        let riderID = profile.id
        athleteSyncing = true; defer { athleteSyncing = false }
        do {
            let remote = try await AppInfo.intervalsClient.athleteSettings(connection: connection)
            guard self.profile.id == riderID, self.connection?.athleteID == connection.athleteID else { return }
            athleteSyncNeedsReconnect = false
            applyAthleteSettings(remote)
        } catch IntervalsError.authentication {
            athleteSyncNeedsReconnect = true
        } catch {
            if manual { errorMessage = error.localizedDescription }
        }
    }

    /// Applies remote values to the selected rider (the one who owns the connection). Returns what changed; does nothing while a ride is busy.
    @discardableResult func applyAthleteSettings(_ remote: IntervalsAthleteSettings) -> AthleteSync.Changes {
        guard !isBusy, athleteSync.enabled, connection != nil, let rider = riders.first(where: { $0.id == profile.id }) else { return AthleteSync.Changes() }
        let (changes, state) = AthleteSync.changes(remote: remote, state: athleteSync.state, rider: rider)
        if !changes.isEmpty {
            let updated = AthleteSync.applying(changes, to: rider)
            do {
                try store.saveProfile(updated)
                if let index = riders.firstIndex(where: { $0.id == updated.id }) { riders[index] = updated }
                if profile.id == updated.id {
                    profile = updated
                    if changes.weight != nil { weight = updated.weightKG.map { String($0) } ?? "" }
                    if changes.ftp != nil { ftpSelection = updated.currentFTPID?.uuidString ?? "manual"; manualFTP = "" }
                }
            } catch { errorMessage = error.localizedDescription; return AthleteSync.Changes() }
            athleteSyncNote = AthleteSync.note(for: changes)
        }
        athleteSync.state = state; athleteSync.lastSynced = Date(); saveAthleteSync()
        return changes
    }
}
