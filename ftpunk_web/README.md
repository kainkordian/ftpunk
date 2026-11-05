# FTPunk Web

The browser edition of FTPunk: FTP ramp tests on a smart trainer through Web Bluetooth (Chrome), structured workouts, free ERG and
resistance rides, history and progress. It follows the native iPhone and Mac app (the code in `../Sources` and `../App` wins when this
file and the code disagree): the same Home, Pre-flight, Cockpit, Result, Progress and Settings screens, the same workout library, the same
portable backups. Everything stays in this browser. There is no server, no account and no analytics; the only network calls go to
Intervals.icu, and only after you connect and confirm. The story mode (Lowline, Cyclepunk) was removed on 2026-11-05; its data fields stay
in backups unchanged (`../contracts/README.md`, "Story fields are legacy").

**The FTP test is the core feature.** Three ramp presets (25, 15 and 20 W/min), the scoring (best complete 60 seconds, time weighted) and the
**72 % estimate** are unchanged. New tests always use 72 %; recordings made with 75 % still load and show their own factor.

This directory is self-contained: it has no runtime packages and no build step, and no Node. The development tools are Python 3 and Google Chrome.

## Run

```sh
cd ftpunk_web
python3 tools/serve.py          # http://localhost:8080 in Chrome
```

Browser storage belongs to the origin, so keep the same port to keep your riders and recordings. Opening `index.html` through `file://`
does not work. Web Bluetooth needs a secure context (localhost or HTTPS) and a user-started device chooser.

A device-free walkthrough: Settings → About, activate the About card ten times to unlock **Debug**; mock sensors turn on. Rides then run
on simulated sensors (the playback speed and signal scenario are in the pre-flight and in the cockpit's "⋯" menu), are marked as debug
recordings and never upload. Without a trainer you can also open a preview scenario (below).

For a live ride: close other apps that control the trainer, connect the trainer from the Devices pill (the app checks ERG support and
asks for control), optionally a power meter (then choose power matching or recording only) and a heart-rate strap, then pick a ride on Home.
The pre-flight lists what is missing and keeps Start disabled with the reason above it. Keep the tab visible: a live ride interrupts and tries
to release the trainer if the tab is hidden. Validate pairing, target changes and Stop at a low load before a maximal test.

## Screens

Hash routes: `#/home`, `#/progress`, `#/settings` (a sidebar from 860 px wide, otherwise a tab bar), pushed screens `#/preflight/<ftpTest|freeERG|resistance|workout/<ref>>`,
`#/ride`, `#/result`, `#/activity/<id>`. First launch asks for a name, optional weight and FTP.

- **Home:** rider chip and rider sheet, Devices pill, Today and Upcoming from the Intervals.icu cache (refreshes when over an hour old), the FTP card with
  the retest advice (after eight weeks), quick rides, the 14 classic workouts by category with a detail sheet (profile, steps with % FTP and watts, main set),
  and My workouts (imported JSON for now).
- **Pre-flight:** checklist for every ride, start blockers in the order a rider can fix them, protocol recommendation by weight, workout intensity ±5 within 50–150 %.
- **Cockpit:** target and actual, step countdown, phase timeline, workout profile with a progress marker, Pause/Resume, Stop & save, hold-to-finish for the ramp.
- **Result:** the training result first (delta against the current FTP), then what it changes, then sharing; adopt the FTP.
- **Progress:** FTP trend per rider, activity filters, rows with badges, delete with confirmation, activity detail.
- **Settings:** riders, devices and power source, ride display (theme, extra-large numbers), Intervals.icu, backup export/import, debug, about.

## Preview scenarios

`?scenario=<name>` boots the real app against an in-memory store seeded with a made-up rider (Alex, 71 kg, 230 W). It never reads or writes the real
database or settings. Names: see `src/ui/scenarios.mjs` (`home`, `home-empty`, `preflight-ftp`, `ride-ftp`, `ride-workout`, `result`, `progress`, `settings`, ...).
`python3 tools/capture.py OUT_DIR` writes a PNG per scenario at 390×844 and 1280×800 with headless Chrome. Taking screenshots needs the owner's permission
(`../AGENTS.md`); use `--dry-run` to print the commands.

## Tests and build

```sh
python3 tools/test.py     # static checks, then every suite in real headless Chrome (real IndexedDB, DOMParser, WebCrypto)
python3 tools/build.py    # empties dist/ and copies the static site into it
python3 tools/serve.py --dist
```

`tools/test.py` needs Google Chrome (the macOS app, or `google-chrome` / `chromium` on PATH). It starts `tools/serve.py` in test mode, opens `/tests/`, and
waits for the page to POST its result to `/__test-result` (only `serve.py --test` accepts that). It exits non-zero on a failure or after five minutes.
The static checks cover import paths, orphaned modules, the service worker's precache list, asset references, byte-identical fixture copies and the absence of story wording.
Opening `http://localhost:8080/tests/` by hand runs the same suites. Every `tests/*.test.mjs` is picked up automatically.

**Shared fixtures.** Where native logic is ported, a Swift test writes a golden file into `../contracts/fixtures/` (`FTPUNK_WRITE_FIXTURES=1 swift test --filter ...`);
the web keeps a byte-identical copy in `tests/fixtures/` (the test run fails if they differ) and compares its own output field for field: the workout library
(`workout-library-250w.json`) and the workout preview texts, groups and profile bars (`workout-preview-250w.json`). Never edit a fixture by hand.
GitHub Pages serves `dist/` through `../.github/workflows/pages.yml`, which runs `tools/test.py` before it builds.

## Structure

| Path | Purpose |
| --- | --- |
| `src/app.mjs` | Boot only: open storage, build the app model, register the screens, start the shell, `?scenario=` |
| `src/app-model.mjs` | State and actions the screens call: riders, FTP, pre-flight, starting rides, workouts, calendar, recordings (no DOM) |
| `src/domain.mjs`, `src/protocol.mjs`, `src/bluetooth.mjs`, `src/controller.mjs` | Ramp engine and FTP analysis, packet decoding, Web Bluetooth, ride ownership |
| `src/catalog.mjs` | The classic workout library (flat 50 % warm-ups), intensity labels, retarget example |
| `src/training.mjs`, `src/workouts.mjs` | Training plans, JSON/Intervals imports, cached workouts, scheduled dates |
| `src/rules/presentation.mjs`, `home.mjs`, `progress.mjs`, `preview.mjs`, `preflight.mjs` | Pure rules ported from the native `Sources/FTPunkDomain`; no DOM |
| `src/storage.mjs`, `src/memory-store.mjs`, `src/archive.mjs` | IndexedDB (version 4), the in-memory store for scenarios, portable archive v1–v3 |
| `src/export.mjs`, `src/intervals.mjs`, `src/scene.mjs` | CSV/TCX/JSON download, Intervals.icu client, live power chart |
| `src/preview-fixtures.mjs` | Deterministic riders and recordings for scenarios |
| `src/ui/shell.mjs` | Hash router, nav, live-ride bar, notices, sheets, ride guards, `registerRoute` |
| `src/ui/components.mjs`, `charts.mjs`, `sheets.mjs` | Shared view pieces, SVG charts, rider/devices/protocol/info sheets |
| `src/ui/home.mjs`, `library.mjs` | Home, onboarding; the library, Today, Upcoming, My workouts, workout detail sheet |
| `src/ui/preflight.mjs`, `ride.mjs`, `result.mjs`, `progress.mjs`, `settings.mjs` | The other screens |
| `src/ui/scenarios.mjs` | Preview scenarios, one marked block per feature plan |
| `src/ui/*.css` | `base.css` (tokens: colours in light/dark pairs, spacing, radii, type) and one stylesheet per module |
| `tests/` | `harness.mjs`, `suite.mjs` and `storage-suite.mjs`, the `*.test.mjs` files, `fixtures/` |
| `tools/` | `serve.py`, `test.py`, `build.py`, `capture.py` |

Extension points for features added later: `registerRoute(name, spec)`, `registerPreflightRows(fn)` (pre-flight), `registerSettingsSlot('rideDisplay', fn)`,
`model.workoutResolvers.set(prefix, fn)` (workout references such as `custom:<id>`), `model.hooks.saved` (after a recording is saved), and the scenario blocks.
IndexedDB version 4 already holds `customWorkouts` (index `riderID`), `credentials` and `riderSettings`; trainer warmth is not stored.

## Not verified

No screen of this version has been looked at by a person (the capture tool was built, not run). The tests read the DOM and check layout bounds in headless Chrome; they do
not judge appearance. Physical trainer, power meter and heart-rate behaviour, the Intervals.icu browser calls with a real key (CORS is documented as allowed for localhost and
github.io), the service worker's update path and Web Locks across real tabs have not been exercised. The workout detail sheet has no axis labels on the profile chart
(the native chart has an optional one); intensity is changed in the pre-flight and cockpit, as in the native app.

References: [Chrome Web Bluetooth](https://developer.chrome.com/docs/capabilities/bluetooth), [page lifecycle](https://developer.chrome.com/docs/web-platform/page-lifecycle-api), [Screen Wake Lock](https://www.w3.org/TR/screen-wake-lock/), [Intervals.icu API](https://intervals.icu/api-docs.html).
