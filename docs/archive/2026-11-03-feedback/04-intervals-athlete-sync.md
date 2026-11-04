# 04 — Use FTP and weight from Intervals.icu

## Goal

When Intervals.icu is connected, the rider's **FTP and weight come from Intervals.icu**,
and they stay editable in FTPunk. Local edits must not get overwritten by the next
refresh unless the value on Intervals.icu has actually changed.

## Current state

- `IntervalsClient.connect(apiKey:)` calls `GET /api/v1/athlete/0` but decodes only
  `id` and `name`. The OAuth exchange (`exchange`) gets only `id` and `name`.
- There is one global `IntervalsConnection` (`AppModel.connection`), but there are
  several local riders (`RiderProfile` with `weightKG`, `ftpHistory`, `currentFTPID`).
- FTP history entries carry a `source: String` (`FTPEntry`).
- Workouts already refresh hourly through `SyncPolicy.shouldRefresh` →
  `AppModel.refreshWorkoutsIfNeeded()`.

## Design

### 1. Which rider is linked

Sync applies only to **one linked rider**: the rider who was selected when the account
was connected. Store `linkedRiderID: UUID` alongside the connection (in `UserDefaults`
keyed by athleteID, or in `LocalStore`; **not** in the Keychain blob, so old
connections still decode). If the key is missing for an existing connection, use the
currently selected rider and save that. Settings → Intervals.icu shows
"Linked rider: <name>" with a picker to change it.

### 2. Fetch athlete settings (`FTPunkIntegrations`)

```swift
public struct IntervalsAthleteSettings: Equatable, Sendable {
    public let weightKG: Double?
    public let ftpWatts: Double?
}
public func athleteSettings(connection: IntervalsConnection) async throws -> IntervalsAthleteSettings
public nonisolated static func decodeAthleteSettings(_ data: Data) throws -> IntervalsAthleteSettings
```

- Request: `GET https://intervals.icu/api/v1/athlete/0` with `connection.authorizationHeader`.
- Expected fields (**check them against a real response before relying on them**: log
  the decoded keys once in a debug build, or ask the owner for a sample JSON):
  - weight: `icu_weight` (kg)
  - FTP: `sportSettings[]`. Pick the entry whose `types` contains `"VirtualRide"`,
    otherwise `"Ride"`. Within it, prefer `indoor_ftp` when > 0, otherwise `ftp`.
- Decode leniently: missing/zero/non-finite values become nil and never throw. Reject
  weight outside 30…250 kg and FTP outside 50…1000 W.
- OAuth: check that the granted scopes allow reading the athlete (`SETTINGS:READ` or
  similar). If the request returns 403, skip silently and show a quiet note in
  Settings ("Reconnect to allow reading FTP and weight"). Don't fail the connection.

### 3. Merge rule (pure, `FTPunkDomain`, fully unit-tested)

```swift
public struct AthleteSyncState: Codable, Equatable, Sendable {   // persisted per athleteID
    public var lastSeenFTP: Double?
    public var lastSeenWeight: Double?
}
public enum AthleteSync {
    public struct Changes: Equatable { public var ftp: Double?; public var weight: Double? }
    public static func changes(remote: IntervalsAthleteSettings, state: AthleteSyncState,
                               rider: RiderProfile) -> (Changes, AthleteSyncState)
}
```

- A remote value is applied **only when it differs from `lastSeen*`** (i.e. it changed
  on Intervals.icu since the last sync), and differs from the rider's current local
  value. Then `lastSeen*` is updated.
- That way:
  - First connect: Intervals.icu values are applied.
  - The rider edits FTP or weight locally (or adopts a ramp-test result): the local value
    stays, because the remote value hasn't changed.
  - The rider changes FTP on Intervals.icu later: it's applied at the next sync.
- FTP is applied as a new `FTPEntry(watts:, source: "Intervals.icu")`, made current.
  Never edit or delete existing history entries. Weight sets `rider.weightKG`.
- Compare FTP with a 0.5 W tolerance and weight with 0.05 kg, to avoid churn.

### 4. When to sync

- Right after a successful connect (`acceptConnection`).
- Together with each workout refresh (`refreshWorkoutsIfNeeded` / `downloadWorkouts`).
- Never while a ride is active (`isBusy`). The session configuration snapshot stays
  immutable.
- After applying: `persistProfile()`, and show a one-line, non-modal note on Home or in
  Settings: "FTP 262 W and weight 71.5 kg updated from Intervals.icu".

### 5. UI (`SettingsView.intervalsSection`, `RiderSheet`)

- Settings → Intervals.icu, when connected:
  - "Linked rider" picker.
  - Toggle "Use FTP and weight from Intervals.icu" (default on, persisted per
    athleteID). Off = never apply.
  - "Last synced …" plus a "Sync now" button.
- `RiderSheet` (FTP/weight editing): under the linked rider's fields, a caption
  "From Intervals.icu · edit to override". The fields stay fully editable.
- Update `SettingsTopic.intervals` copy. It currently says uploads never change FTP or
  weight **on Intervals.icu**. That stays true; add "FTPunk reads your FTP and weight
  from Intervals.icu; you can still change them here."

## Tests

- `decodeAthleteSettings`: VirtualRide with `indoor_ftp`, Ride only, missing
  sportSettings, zero/negative/out-of-range values, weight missing.
- `AthleteSync.changes`: first sync applies both; local edit survives an unchanged
  remote; remote change applies; tolerance; toggle off (handled by the caller, so test
  the caller-side guard where it is).
- Rider-linking fallback for a connection without a stored `linkedRiderID`.
- No change to `SessionConfiguration` of a running ride (existing tests cover snapshots;
  add one that sync is skipped while `isBusy`).

## Out of scope

Writing FTP or weight back to Intervals.icu.
