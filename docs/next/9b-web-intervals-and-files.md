# Plan 9b: web Intervals.icu per rider, upload prompt, FTP/weight sync, FIT export

**Runs after plan 8 is merged, in parallel with 9a and 9c.** Size: M.
Read "The web parity project" in [8-web-foundation.md](../archive/2026-11-05-web/8-web-foundation.md) first; its rules apply here.

## Files this plan owns

May edit: `src/intervals.mjs`, `src/export.mjs`, new `src/fit.mjs`, new `src/rules/upload.mjs`,
new `src/rules/athlete-sync.mjs`, `src/ui/result.mjs`, `src/ui/progress.mjs`, `src/ui/settings.mjs` and their CSS,
this plan's block in `src/ui/scenarios.mjs`, its own tests and fixtures. Native side: new Swift test files only.
`storage.mjs`: use the `riderSettings` store plan 8 created; don't change the schema.

## Facts already checked (2026-11-05)

- Intervals.icu answers CORS preflight for `http://localhost:8080` and `https://kainkordian.github.io` with
  `Authorization` and `Content-Type` allowed, for GET and POST. Browser calls are possible. Not yet tried with a
  real key from a browser.
- Browsers send their own User-Agent and don't let scripts set it; no change needed.
- Field names (verified on a live account for native): `icu_weight`; `sportSettings[].types`, `ftp`, `indoor_ftp`
  (`indoor_ftp` wins when present). See `IntervalsClient.swift` and `AthleteSync.swift`.

## 1. One connection per rider

Native: `CredentialVault.swift` (`rider:<uuid>` items), `AppModel+IntervalsSync.swift`.

- `IntervalsClient` holds a map `riderID → { athleteID, name, authorization }`. API key only (no OAuth on the web).
- **By default the key stays in memory only**, as today; after a reload the rider reconnects.
- **Opt-in "Remember on this browser"** (per rider, off by default, a checkbox under the key field): the key is
  encrypted with AES-GCM using a WebCrypto key generated with `extractable: false`; the `CryptoKey` object and the
  ciphertext (with its IV) are stored in the `credentials` store plan 8 created. Never localStorage, never in
  backups, rollback backups, logs, queued jobs or error messages. Disconnect deletes the record; so does deleting the
  rider. If decryption fails, delete the record and ask to reconnect.
- The connect sheet says in one line what remembering protects against (copying the browser's files) and what not
  (a script running on the same site), and that `kainkordian.github.io` is shared with the owner's other GitHub Pages
  sites.
- Add a Content-Security-Policy `<meta>` to `index.html`: `default-src 'self'; connect-src 'self'
  https://intervals.icu; img-src 'self' data: blob:; style-src 'self'; script-src 'self'; object-src 'none';
  base-uri 'none'; form-action 'none'`. Fix anything it breaks (inline styles/scripts).
- Settings → Intervals.icu shows the selected rider's connection: connect with key, disconnect, account name,
  the per-rider "Ask to upload after each ride" toggle (`riderSettings.askToUpload`, default on), and the
  sync toggle.
- Calendar download and Today/Upcoming use the selected rider's connection only. Cached workout ids keep the
  existing `intervals:<account>:<rider>:<event>` form.
- Migrate: the single old connection disappears on reload anyway (memory only); no data migration needed. Approved
  queued jobs keep their frozen account and still only retry while that account is connected for that rider.

## 2. Upload prompt after every ride

Port `UploadPromptRule.swift` to `src/rules/upload.mjs` with its tests (`IntervalsPerRiderTests.swift`):
ask only when the ride's rider has a connection, `askToUpload` is on, no job exists, not a mock ride, FTP tests
with an estimate, workouts/free rides ≥ 300 s that completed or were aborted, never interrupted rides.

The consent dialog (native `result-upload-prompt` scenario) names the rider and the destination account, offers
Upload or Keep local, and never uploads by itself. When the rider has no connection, the result screen shows a
quiet "Connect Intervals.icu to upload" link instead of a dialog. Upload stays **TCX** (roadmap decision).

## 3. FTP and weight sync

Port `AthleteSync.swift` and `AthleteSyncTests.swift` to `src/rules/athlete-sync.mjs`. On connect and on Home
refresh (`SyncPolicy.shouldRefresh`: older than an hour, never during a ride) read the athlete, apply changed FTP
and weight to the linked rider as native does (local edits win until the remote value changes again), show the
note ("FTP 230 W and weight 71.0 kg updated from Intervals.icu"). Uses the `riderSettings.sync` record.

## 4. FIT export

Port `Sources/FTPunkStorage/FITEncoder.swift` to `src/fit.mjs` (no dependencies; CRC, definition and data messages,
file_id, record, lap, session, activity, as native).

- **Byte parity:** add a Swift test `FITFixtureTests.swift` that encodes two fixed sessions (an FTP test with an
  external meter and HR, a workout with trainer power only) and writes them to `contracts/fixtures/*.fit`
  (`FTPUNK_WRITE_FIXTURES=1`, else compare). The JS encoder must produce byte-identical files from the same
  session JSON (also written by the Swift test).
- Export controls (native `ActivityExportControls.swift`): FIT, TCX, CSV, JSON from the result screen and the activity
  detail. File names as native. Use a download link (`download` attribute); offer the Web Share API with files
  where `navigator.canShare({ files })` is true.
- Add a short note next to FIT: "For COROS, Garmin or Strava: upload this file in their web app."

## 5. Scenarios

Add `result-upload-prompt`, `settings-intervals-connected`, `settings-intervals-synced`, `progress-detail-export`.

## Acceptance

- `python3 tools/test.py` and the native `swift test` plus both builds pass.
- FIT fixtures are byte-identical.
- Tests prove: without "Remember" no credential reaches IndexedDB or localStorage; with it, only ciphertext and a
  non-extractable `CryptoKey` are stored (no plaintext key anywhere in the database); no credential reaches an
  archive, a rollback backup or a queued job; one rider's ride can never
  be uploaded to another rider's account; the prompt rule matches native for every case in the Swift tests.

## Report

Test counts, fixture results, deviations from native, and the owner checks still needed (real key in Chrome,
a FIT file uploaded to COROS).
