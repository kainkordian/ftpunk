import Foundation
import Testing
import FTPunkDomain
import FTPunkIntegrations
import FTPunkStorage
@testable import FTPunkApp

private func decode(_ json: String) throws -> IntervalsAthleteSettings {
    try IntervalsClient.decodeAthleteSettings(Data(json.utf8))
}

@Test func athleteSettingsPreferIndoorFTPOfVirtualRide() throws {
    let json = #"{"icu_weight":71.5,"sportSettings":[{"types":["Ride","VirtualRide"],"ftp":250,"indoor_ftp":240},{"types":["Run"],"ftp":400}]}"#
    #expect(try decode(json) == IntervalsAthleteSettings(weightKG: 71.5, ftpWatts: 240))
    let outdoorOnly = #"{"sportSettings":[{"types":["Ride"],"ftp":262,"indoor_ftp":0}]}"#
    #expect(try decode(outdoorOnly) == IntervalsAthleteSettings(weightKG: nil, ftpWatts: 262))
    let virtualWins = #"{"sportSettings":[{"types":["Ride"],"ftp":300},{"types":["VirtualRide"],"ftp":255}]}"#
    #expect(try decode(virtualWins).ftpWatts == 255)
}

@Test func athleteSettingsDecodeLeniently() throws {
    #expect(try decode("{}") == IntervalsAthleteSettings(weightKG: nil, ftpWatts: nil))
    #expect(try decode(#"{"icu_weight":0,"sportSettings":[{"types":["Ride"],"ftp":-5}]}"#) == IntervalsAthleteSettings(weightKG: nil, ftpWatts: nil))
    #expect(try decode(#"{"icu_weight":12,"sportSettings":[{"types":["Ride"],"ftp":5000}]}"#) == IntervalsAthleteSettings(weightKG: nil, ftpWatts: nil))
    #expect(try decode(#"{"icu_weight":"heavy","sportSettings":"none"}"#) == IntervalsAthleteSettings(weightKG: nil, ftpWatts: nil))
    #expect(try decode(#"{"icu_weight":true,"sportSettings":[{"types":["Ride"],"ftp":true}]}"#) == IntervalsAthleteSettings(weightKG: nil, ftpWatts: nil))
    // A bad indoor value falls back to the outdoor one.
    #expect(try decode(#"{"sportSettings":[{"types":["Ride"],"ftp":250,"indoor_ftp":9999}]}"#).ftpWatts == 250)
    #expect(throws: IntervalsError.self) { try decode("[1]") }
}

private func rider(ftp: Double? = nil, weight: Double? = nil) -> RiderProfile {
    var rider = RiderProfile(id: UUID(), name: "A", weightKG: weight)
    if let ftp { let entry = FTPEntry(watts: ftp, source: "Manual"); rider.ftpHistory = [entry]; rider.currentFTPID = entry.id }
    return rider
}

@Test func firstSyncAppliesBothValues() {
    let (changes, state) = AthleteSync.changes(remote: .init(weightKG: 71.5, ftpWatts: 262), state: .init(), rider: rider(ftp: 200, weight: 80))
    #expect(changes == .init(ftp: 262, weight: 71.5))
    #expect(state == .init(lastSeenFTP: 262, lastSeenWeight: 71.5))
    #expect(AthleteSync.note(for: changes) == "FTP 262 W and weight 71.5 kg updated from Intervals.icu")
}

@Test func localEditsSurviveAnUnchangedRemote() {
    let state = AthleteSyncState(lastSeenFTP: 262, lastSeenWeight: 71.5)
    let (changes, next) = AthleteSync.changes(remote: .init(weightKG: 71.5, ftpWatts: 262), state: state, rider: rider(ftp: 255, weight: 73))
    #expect(changes.isEmpty && next == state)
}

@Test func remoteChangeAppliesAndToleranceAvoidsChurn() {
    let state = AthleteSyncState(lastSeenFTP: 262, lastSeenWeight: 71.5)
    let (changed, next) = AthleteSync.changes(remote: .init(weightKG: 71.5, ftpWatts: 270), state: state, rider: rider(ftp: 255, weight: 73))
    #expect(changed == .init(ftp: 270, weight: nil) && next.lastSeenFTP == 270)
    let (jitter, _) = AthleteSync.changes(remote: .init(weightKG: 71.54, ftpWatts: 262.4), state: state, rider: rider(ftp: 255, weight: 73))
    #expect(jitter.isEmpty)
    // Remote changed but already equals the local value: nothing to apply, but it is remembered.
    let (same, remembered) = AthleteSync.changes(remote: .init(weightKG: nil, ftpWatts: 270), state: state, rider: rider(ftp: 270.2))
    #expect(same.isEmpty && remembered.lastSeenFTP == 270)
    // Missing remote values leave the state alone.
    let (none, kept) = AthleteSync.changes(remote: .init(weightKG: nil, ftpWatts: nil), state: state, rider: rider())
    #expect(none.isEmpty && kept == state)
}

@Test func applyingAddsAnEntryWithoutTouchingHistory() {
    let original = rider(ftp: 200, weight: 80)
    let updated = AthleteSync.applying(.init(ftp: 262, weight: 71.5), to: original)
    #expect(updated.ftpHistory.count == 2 && updated.ftpHistory[1] == original.ftpHistory[0])
    #expect(updated.currentFTP?.watts == 262 && updated.currentFTP?.source == "Intervals.icu" && updated.weightKG == 71.5)
}

@Test func linkedRiderFallsBackToTheSelectedRider() {
    let a = RiderProfile(id: UUID(), name: "A"), b = RiderProfile(id: UUID(), name: "B")
    #expect(AthleteSync.linkedRiderID(stored: nil, riders: [a, b], selected: b.id) == b.id)
    #expect(AthleteSync.linkedRiderID(stored: a.id, riders: [a, b], selected: b.id) == a.id)
    #expect(AthleteSync.linkedRiderID(stored: UUID(), riders: [a, b], selected: b.id) == b.id) // stored rider was deleted
}

@Test func connectionsReadSettingsWithApiKeysOrTheScope() {
    #expect(IntervalsConnection(athleteID: "1", athleteName: "A", apiKey: "k").canReadAthleteSettings)
    #expect(!IntervalsConnection(athleteID: "1", athleteName: "A", accessToken: "t", scopes: ["ACTIVITY:WRITE"]).canReadAthleteSettings)
    #expect(IntervalsConnection(athleteID: "1", athleteName: "A", accessToken: "t", scopes: ["SETTINGS:READ"]).canReadAthleteSettings)
}

@Test @MainActor func syncAppliesToTheLinkedRiderAndIsSkippedDuringARide() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.connection = IntervalsConnection(athleteID: "i1", athleteName: "A", apiKey: "k")
    await model.start()
    #expect(model.isBusy)
    #expect(model.applyAthleteSettings(.init(weightKG: 70, ftpWatts: 250)).isEmpty)
    #expect(model.profile.currentFTP?.source != "Intervals.icu")
    model.stop()
    let changes = model.applyAthleteSettings(.init(weightKG: 70, ftpWatts: 251))
    #expect(changes == .init(ftp: 251, weight: 70))
    #expect(model.profile.currentFTP?.watts == 251 && model.profile.weightKG == 70 && model.weight == "70.0")
    #expect(model.athleteSyncNote == "FTP 251 W and weight 70.0 kg updated from Intervals.icu")
    // Disabled: nothing applies.
    model.athleteSync.enabled = false
    #expect(model.applyAthleteSettings(.init(weightKG: 60, ftpWatts: 300)).isEmpty)
}
