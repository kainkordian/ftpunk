# Plan 8: web foundation (story out, native layout in, ready for parallel work)

**Run first, alone.** Plans 9a, 9b and 9c start only after this one is merged. Size: L.

## Goal

Bring `ftpunk_web/` to the native app's structure and core behaviour, without the features that
plans 9a–9c add. Afterwards the web app has the native screens (Home, Progress, Settings, pre-flight,
cockpit, result), no story, the native workout library and preview, and a file layout in which
three agents can work at once without editing the same files.

## The web parity project (read this even if you only run 9a, 9b or 9c)

- **Target:** the native app as it is in this repo on 2026-11-05. When this plan and the native code
  disagree, the native code wins. Native sources are in `Sources/` (logic) and `App/` (screens).
- **Local only.** No server, no accounts, no analytics, no external scripts, fonts or CDNs. Data lives in
  the browser (IndexedDB). The only network calls are to Intervals.icu, and only after the rider confirms.
- **The story is scratched.** No Lowline, Cyclepunk, City, XP, beats, patches or receipts in the UI.
- **The FTP test is the core feature.** Don't change ramp scoring, the three ramp presets, freshness rules or
  the estimate. New tests always use **72 %**. The 72/75 picker goes; recordings with 0.75 still load and
  show their own factor.
- **No toolchain.** Plain ES modules, no npm dependencies, no bundler, **no Node**. Dev tools are Python 3 and
  Google Chrome. Tests run in real headless Chrome (real IndexedDB, `DOMParser`, WebCrypto) with
  `python3 tools/test.py` (step 1). Don't install anything.
- **Parity through shared fixtures.** Where native logic is ported, a Swift test writes a golden fixture into
  `contracts/fixtures/` (pattern: `HomeAndLibraryTests.swift`, `FTPUNK_WRITE_FIXTURES=1`, otherwise
  compare), the web copies it to `ftpunk_web/tests/fixtures/` and its test compares against it.
  Never edit a fixture by hand.
- **Done** means: `cd ftpunk_web && python3 tools/test.py` passes, `python3 tools/build.py` works, and the native
  `swift test` plus both `xcodebuild` builds from AGENTS.md still pass (they read web fixtures).
- **No visual review** without the owner's permission (AGENTS.md). Build the capture tool (step 7) but
  don't run it to take screenshots. Report what was not looked at.
- Don't commit unless the owner asks. Don't create new docs; update `ftpunk_web/README.md`,
  `contracts/README.md` and the roadmap's "Where it stands".

## Steps

### 1. Test runner without Node, then baseline

- Write `tools/test.py`: run `tools/check.mjs`'s checks ported to Python (syntax via Chrome is enough; keep the
  import-path and asset-reference checks), start `tools/serve.py` on a free port, launch Google Chrome headless
  (`--headless=new`, a temporary `--user-data-dir`, `--remote-debugging-port=0` or similar so it stays alive), open
  `/tests/`, and wait until the page reports the result. Let the page POST its final result (passed, failed, failure
  texts) to a `/__test-result` endpoint that only `serve.py --test` accepts; print it, exit non-zero on failure or
  after a 5-minute timeout, always kill Chrome and the server. Chrome path: macOS app bundle, else `google-chrome` /
  `chromium` on PATH (for CI on Ubuntu).
- Remove `package.json`'s Node scripts and `tests/run.mjs`; the suites stay browser modules. Drop the `node:fs`
  branches in `tests/suite.mjs`.
- Run it before touching anything else and record the count (84 tests plus the IndexedDB suite on 2026-11-05).
- Add a `python3 ftpunk_web/tools/test.py` step to the `build` job of `.github/workflows/pages.yml` (Ubuntu runners
  have Chrome) before the build step, so a failing suite never deploys.
- `tools/build.py` copies into `dist/` without removing old files; make it start from an empty `dist/`.
- Read `src/app.mjs`, `src/domain.mjs`, `src/controller.mjs`, `src/storage.mjs`, `src/archive.mjs` fully.
  Lines are long; read with an editor view, not `head`.

### 2. Remove the story

- Delete `src/city.mjs`, the City tab, rewards/receipt views, XP and Last Light code paths in `app.mjs`,
  `training.mjs` (`LAST_LIGHT_MS`, `creditSession`, `progressMilliseconds` usage in the UI), `scene.mjs`
  story art, and the "adventure" toggle.
- **Keep the data contract** exactly as `contracts/README.md` → "Story fields are legacy" describes for native:
  `cycleProgress` and the three activity fields are validated, stored and exported **unchanged**; new
  recordings omit them; a legacy recording still credits its rider's ledger idempotently on save/import.
  Keep `validateProgress`/`creditSession` as data code for that. Archive version selection stays as documented.
- Delete or rewrite the story tests; keep every archive round-trip test (v1, v2, v3 fixtures) green.

### 3. Split `app.mjs` and the CSS so later plans don't collide

Create this layout (names are binding; 9a–9c rely on them):

| Path | Content | Later owner |
|------|---------|-------------|
| `src/ui/shell.mjs` | Router (hash routes), tab bar/sidebar, live-ride link, notices, dialogs, `registerRoute` | 8 only |
| `src/ui/home.mjs` | Home: rider chip, Today, FTP test card, quick rides, library | 9c (library section) |
| `src/ui/library.mjs` | The library section and workout detail sheet, called from `home.mjs` | 9c |
| `src/ui/preflight.mjs` | Pre-flight checklist for every ride kind | 8 |
| `src/ui/ride.mjs` | Cockpits (FTP test and workout), pause/stop, live chart | 9a |
| `src/ui/result.mjs` | Result screen | 9b (export/upload controls) |
| `src/ui/progress.mjs` | Trend chart, activity list, activity detail | 9b (export/upload controls) |
| `src/ui/settings.mjs` | Settings sections | 9b (Intervals section) |
| `src/ui/components.mjs` | Shared bits: buttons, pills, metric tiles, phase timeline, hold-to-confirm | 8 only |
| `src/ui/*.css` | One stylesheet per module above plus `base.css` (tokens) | same as module |
| `src/ui/scenarios.mjs` | Preview scenarios (step 7) | each plan adds its own scenario in its own block |

`app.mjs` shrinks to boot: open storage, build the app model, start the shell. Pure logic stays out of
`src/ui/`. Keep `index.html` and `sw.js` precache lists in step with the new files (`tools/check.mjs` checks
asset references; extend it to check the service-worker list).

### 4. Native layout and design

Port the native information architecture from `App/Features/Shell/Navigation.swift` and the screens in
`App/Features/`:

- Destinations **Home, Progress, Settings** (sidebar on wide windows, bottom tab bar on narrow ones), with
  pre-flight, ride, result and activity detail as pushed screens.
- **Home** (`HomeView.swift`, `TodaySection.swift`, `WorkoutLibrarySection.swift`): rider chip and rider sheet,
  Today (`TodayWorkouts` in `HomeRules.swift`), the FTP test card with retest advice (`RetestAdvice`),
  quick rides (free ERG, resistance), the classic library by category, Upcoming (Intervals cache). Leave a
  marked placeholder where 9c adds "My workouts".
- **Onboarding** (`OnboardingView.swift`): first launch with no rider asks name, optional weight and FTP.
- **Pre-flight** (`PreflightView.swift`): checklist rows and the start blockers from `StartReadiness` /
  `StartBlocker` (`PresentationRules.swift`), protocol recommendation by weight (`ProtocolRecommendation`),
  cadence guard. No 72/75 picker.
- **Result** (`ResultView.swift`): order and deltas from `ResultDelta`; adopt FTP; leave a marked slot
  for 9b's export/upload controls.
- **Progress** (`ProgressTabView.swift`, `ProgressRules.swift`): trend per rider (`TrendMetric`), filter chips
  (`ActivityFilter`), rows (`ActivityRowModel`), delete with confirmation. Slot for 9b's export controls.
- **Settings** (`SettingsView.swift`): riders, devices and power source, matching preference, appearance,
  backup export/import (existing), debug mode. Slot for 9b's Intervals section.
- Design tokens from `App/DesignSystem/Tokens.swift`, `ZonePalette.swift` and `App/Theme.swift` become CSS
  custom properties in `base.css` (colours light/dark, spacing, radii, type scale). Use system fonts.
- Keep what the web already does well: keyboard access, labels, `prefers-reduced-motion`, live-region
  announcements, wake lock, cross-tab ride lease, hidden-tab interruption.

Port pure rules as JS modules with tests mirroring the Swift tests: `src/rules/presentation.mjs`
(`PresentationRulesTests.swift`), `src/rules/home.mjs` (`HomeAndLibraryTests.swift`,
`HomeWorkflowTests.swift`), `src/rules/progress.mjs` (`ProgressTests.swift`).

### 5. Workout library, flat warm-ups and preview

- Replace `starterPlans` with the native catalog (`WorkoutLibrary.swift`). Copy
  `contracts/fixtures/workout-library-250w.json` to `ftpunk_web/tests/fixtures/` and test the JS catalog at
  250 W against it, field for field. The fixture is the truth: warm-ups are flat 50 %, not ramps.
  `contracts/README.md` still says "10 minute warm-up ramp from 50 to 70 %"; correct that sentence.
- Port `WorkoutPreview.swift` (step summaries, % FTP / W text, `mainSetText`) and `WorkoutProfile.swift`
  (the profile chart). Add a Swift test that writes `contracts/fixtures/workout-preview-250w.json` (for every
  classic: `mainSetText`, total duration, step texts with values on and off) and compare in JS.
- Workout detail sheet (`WorkoutDetailSheet.swift`): profile chart, steps, intensity ±5 within 50–150 %.

### 6. Storage upgrade for all later plans

Do the IndexedDB schema bump **once, here**, so 9a–9c never touch the version:

- object store `customWorkouts` (key `id`, index `riderID`), used by 9c;
- object store `credentials` (key `riderID`), used by 9b for remembered Intervals.icu keys (encrypted);
- object store `riderSettings` (key `riderID`): `{ askToUpload: true, sync: { enabled, linkedAccountID,
  lastSynced, state: { lastSeenFTP, lastSeenWeight } } }`, used by 9b;
- preference `trainerWarmthKJ` is **not** stored (warmth resets with the Bluetooth connection, as native).

Migrations must keep existing data; add a storage-suite test for upgrading a v-current database.

### 7. Preview scenarios and the capture tool (built, not run)

- `?scenario=<name>` boots with an in-memory store seeded like native `App/Preview/PreviewScenarios.swift`
  (made-up rider: 71 kg, 230 W). Never touches the real database. Provide at least: `home`, `home-empty`,
  `preflight-ftp`, `ride-ftp` (mock ride mid-ramp), `ride-workout`, `result`, `progress`, `settings`.
- `tools/capture.py`: starts `tools/serve.py` on a free port, runs Google Chrome headless
  (`--headless=new --screenshot --window-size=W,H`) for every scenario at 390×844 and 1280×800, writes PNGs
  to a directory given on the command line. Test it only with `--dry-run` (prints the commands). The owner's
  permission is needed before it is run for real.

### 8. Clean-up and docs

- Remove dead code (`tools/test.py` checks imports; also grep for orphaned CSS classes).
- Rewrite `ftpunk_web/README.md`: what it is now, run, test, scenarios, structure table, what isn't
  verified. Remove "ready to split into a separate repository" wording only if still accurate.
- Update the roadmap's "Where it stands" with one paragraph.

## Acceptance

- `python3 tools/test.py` (including the IndexedDB suite), `python3 tools/build.py`, native `swift test` and both builds pass.
- No string "Cyclepunk", "Lowline", "XP", "City" or "Last Light" in `src/ui/` or `index.html`.
- v1, v2 and v3 archive fixtures import and re-export with story fields unchanged.
- The JS library equals the shared fixture; preview text equals the Swift fixture.
- A new FTP test's configuration always has `ftpFactor: 0.72`.
- `src/ui/` matches the table in step 3 so 9a–9c can start.

## Report

What changed, test counts before/after, anything not ported and why, and what nobody has looked at on a screen.
