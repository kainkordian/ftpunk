# 1 — Intervals.icu per rider, upload prompt after every ride

Two goals, decided by the owner on 2026-11-04:

1. **Every rider profile has its own Intervals.icu connection** (or none). Today there's one
   app-wide connection (`CredentialVault`, Keychain account `personal-connection`), so a
   ride by rider B can be uploaded to rider A's account.
2. **After every finished ride, ask** whether to upload it, if that rider has a connection.
   Today the rider has to find the "Upload to Intervals.icu…" button on the result screen.

Parts A–C are small follow-ups to the athlete sync (archive/2026-11-03-feedback/04). Do D and E first.

## D. One connection per rider

- `CredentialVault`: key the Keychain item by rider: account `rider:<lowercased UUID>`.
  `load(riderID:)`, `save(_:riderID:)`, `clear(riderID:)`, `allRiderIDs()`.
- **Migration, once, on launch:** if `personal-connection` exists, move it to the rider that
  `athleteSync.linkedRiderID` points to (fallback: the selected rider), then delete the old
  item. Do this idempotently, and test it with an in-memory vault (introduce a small
  `CredentialStoring` protocol so tests don't touch the real Keychain).
- `AppModel.connection` becomes the **current rider's** connection (computed from
  `connections[profile.id]`). Switching rider switches account everywhere: Settings, calendar
  download, athlete sync, upload.
- One Intervals account may be linked to **one rider only**. Connecting the same `athleteID`
  to a second rider shows "This Intervals.icu account is already connected to <rider>" and
  doesn't save.
- Athlete sync (FTP/weight): the per-account `AthleteSyncSettings` is now per rider. Drop the
  "Linked rider" picker, because the rider owning the connection *is* the linked rider.
  Migrate the existing settings to that rider.
- Upload jobs already store `accountID`. `flushUploads` runs for **every** rider with queued
  jobs, each with its own connection, not only the selected rider's. Disconnecting a rider
  deletes only that account's pending jobs (as today for the single account).
- Deleting a rider profile also deletes its Keychain item and pending jobs.
- Settings → Intervals.icu shows "Connected as <athlete name> · for <rider name>", with
  Connect/Disconnect for the selected rider. Pre-flight and Home show the state for the
  selected rider.
- Credentials still never go into archives.

## E. Ask after every ride

- When an activity is **finished and saved**, the result screen presents the upload consent
  sheet automatically. The existing `UploadConsent` names the account and rider. Conditions:
  - the session's rider has a connection;
  - the activity isn't a demo or mock;
  - it ended normally: an FTP test with a result, or a workout, free ERG or resistance ride
    that was completed or stopped by the rider after at least 5 minutes;
  - it isn't already queued or uploaded.

  Interrupted rides (lost trainer, crash recovery) are not prompted. The manual button stays
  for them.
- Buttons: **Upload** and **Not now**. "Not now" leaves the manual button on the result screen
  and in the activity detail, as today.
- Per rider, in Settings → Intervals.icu: toggle **"Ask to upload after each ride"**, on by
  default. Off means no prompt, but the manual button still works. **No silent automatic
  upload**: every upload stays an explicit confirmation.
- Make the decision pure and tested: `UploadPromptRule.shouldAsk(session:, hasConnection:,
  askEnabled:, existingJob:) -> Bool`.
- Preview scenario `result-upload-prompt` (and add it to the simulator matrix list).

## Tests for D and E

Vault migration (old item present / absent / already migrated), per-rider connection switch,
duplicate account refused, jobs flushed per account, rider deletion clears its credential,
each `UploadPromptRule` case (FTP result, completed workout, 4-minute free ride, interrupted,
demo, already uploaded, no connection, prompt off).


## A. Ask for `SETTINGS:READ` on OAuth sign-in (owner approved)

- `Sources/FTPunkIntegrations/IntervalsOAuth.swift` (about line 55): scope becomes
  `"ACTIVITY:WRITE,CALENDAR:READ,SETTINGS:READ"`.
- `Tests/FTPunkTests/DebugAndOAuthTests.swift` (about line 61): update the pinned
  string **deliberately**. Don't loosen the test.
- Existing OAuth connections without the scope keep showing "Reconnect to sync FTP
  and weight" (`IntervalsConnection.canReadAthleteSettings`). Check that this text
  says that reconnecting is all it takes.
- Report to the owner: the scope name follows Intervals.icu's documented
  `SETTINGS:READ`. Confirm it on the consent screen during the next real OAuth sign-in.

## B. Field names are verified: update comments and fixture

On 2026-11-04 the owner's real `GET /api/v1/athlete/0` (API-key connection) returned:

- top level: `icu_weight: 71.0` (kg). There are also `weight: null`, `weight_pref_lb`
  and `icu_weight_sync`. Ignore those.
- `sportSettings[]`: each entry has `types: [String]`, `ftp: Int?`, `indoor_ftp: Int?`
  (null when unset), plus `sft_ftp`, `ftp_est_min_secs` and `eFTPSupported`. Ignore
  those. The cycling entry's types are
  `["Ride","VirtualRide","MountainBikeRide","GravelRide","TrackRide","Cyclocross"]`,
  `ftp: 230`, `indoor_ftp: null`. Run, swim and other entries have `ftp: null`.

Tasks:

- `Sources/FTPunkDomain/AthleteSync.swift`: replace "documented from memory and not
  verified" with "verified against a live response on 2026-11-04".
- Add a test with a fixture of exactly that shape. Include the extra keys, the null
  `indoor_ftp`, four sport entries and Ride listed first. Expect weight 71 and FTP 230.
  Add a second case with `indoor_ftp: 250`, which must win over `ftp: 230`.

## C. Send an explicit User-Agent

A request without a browser-like or app User-Agent got **HTTP 403** from intervals.icu
(Python `urllib` default). `URLSession` sends its own UA, so the app likely works today.
Still, set `User-Agent: FTPunk/<marketing version> (<iOS|macOS>)` on every Intervals
request: connect, athlete settings, events, upload, revoke and the OAuth token
exchange. Take the version from `AppInfo` or `Bundle.main`. In the integrations
module, take it as a parameter, since that module can't see the app bundle. Add a test
on the built `URLRequest`s, for example `uploadRequest` and `workoutRequest`.
