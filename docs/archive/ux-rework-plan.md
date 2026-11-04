# FTPunk UX/UI rework plan

Status: approved for implementation, 2 November 2026. Supersedes the navigation section
of [evolution-plan.md](evolution-plan.md) §3. Native iPhone/Mac first; the
web app follows one phase behind (§10).

> **Update, 2 November 2026:** the optional story (Story tab, Home card, receipts, §1, §4, §6 and Phase 5 below) was removed from the native app and replaced by the pixel ride. See [ride-visual-plan.md](ride-visual-plan.md). Story data fields are kept for archive compatibility only.

## 1. Decisions

- **Home is a ride picker.** It shows today's Intervals.icu workout when one is
  scheduled, and lets the rider choose any kind of ride: FTP test, free ERG, resistance,
  or a classic workout from a library grouped by type.
- **The FTP test remains the key feature.** It has a permanent, prominent place on Home,
  gets the most design and test effort, and moves to the top of Home when the rider has
  no FTP yet.
- **The estimate stays at 72 % of the best 60-second ramp power.** This is the protocol
  author's figure. Underestimating FTP is less harmful than overestimating it, and the
  conservative value costs little in workout quality. New tests always use 72 %. The
  75 % setup option is removed; recordings made with 75 % keep and display their
  original factor, and archives keep accepting it.
- **Story is optional and off by default.** It is enabled in Settings. When enabled, Home
  shows a small story card and a Story tab appears. When disabled, there is no tab, no
  card, no receipts and no XP.
- **Retest suggestion after 8 weeks.**
- **No audio/haptic step cues.** Ramp steps change every 12–20 s, which would be noisy.
- **Training and story are part of the test workflow**: the test result feeds library
  targets and (if enabled) story progress, and the verification workflow covers workouts
  and story as thoroughly as the test (§9).
- Existing safety rules are unchanged: Stop is immediate with no confirmation, FTP tests
  cannot be paused, measurement sources are fixed at start, uploads always ask, debug
  tools stay hidden until unlocked, mock rides earn no XP, and story never changes trainer
  targets or rewards high power/test completion.

## 2. What the review found

From the 2 November walkthrough (Mac preview, mock sensors) and code reading:

- Setup is three dense form pages; the Start button can be disabled without saying why.
- Mid-ramp, **Finish ramp** is the most prominent button, which makes ending the test by
  accident the easiest mistake to make. The ride shows total time but not the ramp step.
- The result buries "Use this FTP", doesn't show where the best minute came from, and
  doesn't connect to training or story.
- Five tabs, plus a "Review last ride" bar that never goes away. Train is one long form
  that duplicates rider/device controls from FTP Test. "City" doesn't explain itself.
- Bugs: Mac menus hide their selected value (`SelectionMenu`); "Back to Train" appears in
  FTP tests; the History legend mixes colour and shape scales; Train's FTP field silently
  switches FTP Test setup to manual.

## 3. Principles

1. **One obvious next action per screen**, as a full-width primary button at the bottom.
2. **Defaults over decisions.** Protocol, warm-up and durations are pre-filled from the
   rider, so most tests are just "check, then start". Changes are possible but tucked away.
3. **Glanceable from the saddle.** At 1–2 m, sweating, in the middle of an effort: large
   numbers, few of them, and nothing that moves while you're working out what to tap.
4. **Hard to end a test by mistake, always easy to stop.** Finish ramp needs a deliberate
   gesture; Stop stays a single tap.
5. **Story rewards riding but never gets in the way.** It is quiet during the scored ramp
   and appears after the training result.
6. **Every state can be shown in a screenshot.** Each screen can be reached through a
   seeded preview scenario, so reviews and tests cover everything (§9).

## 4. Information architecture

| iPhone tab / Mac sidebar | Contents |
| --- | --- |
| **Home** (default) | Today's workout, FTP card, ride picker, workout library, story card (if enabled) |
| **Progress** | FTP trend, activity list with filters, activity details (replaces History) |
| **Story** (only when enabled) | Lowline scene, chapter progress, transmissions, receipts (replaces City) |
| **Settings** | Riders, devices & trainer, ride display, story, Intervals.icu, backup, about |

On Home's toolbar, always visible:

- **Rider chip** (initials + name): switch or add riders, edit weight/FTP. This is the only
  place the rider is chosen.
- **Devices pill** (trainer · power · HR status dots): opens one shared Devices sheet that
  replaces the duplicate device rows in FTP setup and Train.

During a ride the tab bar is hidden and the cockpit fills the screen. Minimising it shows a
**live-ride bar** above the tabs ("Ramp · 245 W · 7:20 · Return"), visible only while a ride
is active. Finished rides are reached from Progress.

### 4.1 Home

```
┌───────────────────────────────┐
│ (AL) Alex ▾            ●●○    │  rider chip · devices pill
│                               │
│ TODAY · from Intervals.icu    │
│ ┌───────────────────────────┐ │
│ │ Sweet spot 3×12   62 min  │ │
│ │ ▁▃▆▆▃▆▆▃▆▆▁  profile      │ │
│ │ [▶ Start]                 │ │
│ └───────────────────────────┘ │
│                               │
│ FTP 250 W · 3.33 W/kg         │
│ Tested 12 Oct · 3 weeks ago   │  becomes the retest prompt after 8 weeks
│                    [FTP test ›]│
│                               │
│ Quick ride                    │
│ [Free ERG] [Resistance]       │
│                               │
│ Workouts                      │
│ Endurance · Tempo · Sweet spot│  category chips
│ Over-unders · Threshold · VO2 │
│ ┌──────────┐ ┌──────────┐     │
│ │SS 3×10   │ │SS 2×20   │ …   │  cards: name, duration, profile
│ └──────────┘ └──────────┘     │
│ Upcoming (Intervals) · Mine + │
│                               │
│ ◈ Lowline · 12/20 min  ›      │  story card, only if enabled
└───────────────────────────────┘
```

Order and rules:

1. **Today** – Intervals.icu workouts whose scheduled local date is today, each with name,
   duration, profile and Start. Connected with nothing today: "Nothing planned today" and
   the next upcoming workout. Not connected: a single quiet line, "Connect Intervals.icu in
   Settings to see planned workouts", which the rider can dismiss.
2. **FTP card** – current FTP, W/kg, one status line ("Tested 12 Oct · 3 weeks ago") and an
   "FTP test" button. After 8 weeks the same line becomes the retest prompt, in the warning
   colour ("Tested 13 Nov · 9 weeks ago · time to retest?"). **With no FTP** this card moves
   above Today and becomes the main call to action ("Take an FTP test so workouts fit
   you"). Library workouts then say "Needs FTP" instead of targets.
3. **Quick ride** – Free ERG and Resistance (shown disabled with a reason when the trainer
   doesn't advertise it). The FTP test is not repeated here: it has its button on the FTP card.
4. **Workouts** – the classic library (§5), with category chips and cards; then
   **Upcoming** (Intervals.icu, next 14 days) and **My workouts** (imports, with a "+"
   menu for import and the example JSON).
5. **Story card** – only when story is enabled (§6).

**Intervals.icu sync**: when connected, Home refreshes the 14-day calendar on appear if the
last download is more than an hour old, and on pull-to-refresh. It never refreshes during a
ride. Cached workouts gain an optional `scheduledDate` (local `yyyy-MM-dd`, from the event's
`start_date_local`). Older caches and archives without it remain valid; they appear under
Upcoming without a date until the next download.

First launch with no rider data shows a short onboarding step before Home: name, weight
(optional, needed for W/kg) and FTP if known ("Not sure" leads to the FTP test).

### 4.2 Pre-flight

Every ride passes through one pre-flight screen: a checklist with the Start button always
visible. When Start is disabled, the reason sits directly above it ("Connect your trainer
to start").

Common rows:

- **Rider** – name, weight, FTP used. Edit opens the rider sheet.
- **Devices** – Trainer (required), Power source (Trainer / external meter), Heart rate
  (optional), Cadence: "from trainer" or a neutral "no cadence yet: connect and pedal".
  It is shown as a problem only once devices are connected and cadence is still missing.
- **Story** – only when enabled: "Earns Lowline progress", plus "story stays quiet during
  the ramp" for FTP tests.

FTP test rows (replacing the old Rider → Protocol → Ready steps):

- **Protocol** – the recommended ramp, with its reason ("75 kg → 25 W/min"). Change opens
  the three protocol cards and the "Which protocol, and why?" explanation.
- **Warm-up / cool-down** – values with an Adjust disclosure (the existing 0–60 min inputs
  and manual warm-up watts).
- **Estimate** – "72 % of your best minute" (information only; no picker).
- **Pixel ride** – the Stelvio toggle.

Workout rows: profile chart, duration, FTP used vs current FTP, intensity 50–150 %.
Free ERG rows: starting watts. Resistance rows: starting level.

Debug timing and mock options appear only when debug is unlocked, inside one marked
Debug group.

### 4.3 Ride cockpit, FTP test

Layout per phase, with Stop & save always one tap away in the bottom bar:

| Phase | Hero | Supporting | Bottom bar |
| --- | --- | --- | --- |
| Warm-up | Target W, actual W | HR, cadence, warm-up countdown, full Stelvio scene | Stop |
| Ramp | Target W, actual W | **Step N · ramp time**, next-step countdown ring, MAX 60 S, cadence, HR; compact Stelvio altitude strip, no dialogue | **Hold to finish** · Stop |
| Cool-down / free spin | "Easy" or cool-down W | Provisional result preview, Stelvio summit/descent | Stop & save |
| Interrupted | Reason in plain words | What was saved, whether a result exists | Done |

```
┌───────────────────────────────┐
│ ⌄  RAMP · Step 14   7:20 ramp │  ⌄ minimises to the live-ride bar
│ ▓▓▓▓▓▓▓▓▓░░░░ warm│ramp│cool  │  phase timeline
│ ┌────────────┐┌────────────┐  │
│ │ TARGET     ││ ACTUAL     │  │
│ │   245 W    ││   243 W    │  │
│ └────────────┘└────────────┘  │
│   ◔ +5 W in 7 s               │  countdown ring
│ ┌──────┐ ┌──────┐ ┌────────┐  │
│ │♥ 168 │ │⟳ 88  │ │MAX60 231│ │
│ └──────┘ └──────┘ └────────┘  │
│ ▂▃▃▄▅▅▆ Stelvio strip         │
│ [ Hold to finish ][  ■ Stop  ]│
└───────────────────────────────┘
```

- **Hold to finish**: secondary style, 1.5 s press with a filling ring, a VoiceOver custom
  action, and a keyboard shortcut on Mac. Automatic finish (cadence below 45 rpm for 5 s)
  is unchanged.
- **Cadence guard**: below 60 rpm during the ramp, the cadence tile turns amber with "Ramp
  ends below 45 rpm". This explains the automatic finish before it happens.
- Debug playback controls (including skip warm-up) move into a bottom sheet so they never
  push metrics off screen.

**Workout cockpit** reuses the same layout: step name, step time left, next step preview,
the profile with a progress marker, intensity ±5 %, and Pause/Resume as primary; Stop stays
one tap. **Free ERG** shows ±10 W; **resistance** shows ± level.

### 4.4 Result

Order: training result first, then what it means for training, then story, then sharing.

1. **Estimated FTP 209 W · 2.78 W/kg**, change from the current FTP ("−41 W vs 250 W") and
   "72 % of your best minute, 290 W". The 72–77 % range moves into "How this is calculated"
   so the conservative figure is the one riders take away.
2. **Power chart with the best 60-second window shaded and labelled**, plus phase bands.
3. **Primary: "Use 209 W as Alex's FTP"**, or "Keep 250 W" as secondary text. Adopting
   shows the confirmation inline.
4. **Training hand-off** card (after adopting): "Library workouts now use 209 W", with one
   example (e.g. "Sweet spot 3×10: 225 → 188 W") and "Back to Home".
5. **Story receipt** (only when enabled): XP from this ride, unlocked transmissions, and a
   non-scoring "calibration log" line for any saved test. It is narrative only and gives no
   bonus XP, in line with the rule that test completion isn't rewarded.
6. Upload to Intervals.icu (existing consent sheet), Done.

Debug and interrupted results keep the same layout, with the debug badge at the top and no
adopt/upload. Workout and free-ride results show duration, average/normalised power if
already computed elsewhere (otherwise average power), the chart, story receipt and upload.

## 5. Workout library

A built-in, offline catalog of classic structures, resolved at the rider's current FTP when
shown (as `TrainingPlan.starters` does today) and snapshotted when a ride starts. Names
don't include durations; cards show the computed duration.

Every workout uses a **10 min warm-up ramp 50 → 70 %** and a **5 min cool-down ramp
60 → 40 %**, unless marked otherwise. Recoveries are at 50 %. All percentages are of FTP.

| Category | Workout | Main set |
| --- | --- | --- |
| **Endurance** | Easy spin | Existing: 3 min 45 %, 14 min 55 %, 3 min 40 % (no ramps) |
| | Endurance 30 | Existing: 5 min 50 %, 20 min 65 %, 5 min 40 % (no ramps) |
| | Endurance 60 | 45 min at 68 % |
| **Tempo** | Tempo 3×5 | Existing "Tempo intervals" (3 × 5 min 80 %, 2 min recovery) |
| | Tempo 3×10 | 3 × 10 min at 83 %, 3 min recovery |
| | Tempo 2×20 | 2 × 20 min at 82 %, 5 min recovery |
| **Sweet spot** | Sweet spot 3×10 | 3 × 10 min at 90 %, 5 min recovery |
| | Sweet spot 2×20 | 2 × 20 min at 90 %, 5 min recovery |
| **Over-unders** | Over-unders 3×9 | 3 sets of 3 × (2 min 95 % + 1 min 105 %), 5 min recovery between sets |
| | Over-unders 4×6 | 4 sets of 3 × (1 min 90 % + 1 min 110 %), 4 min recovery between sets |
| **Threshold** | Threshold 2×20 | 2 × 20 min at 97 %, 5 min recovery |
| | Threshold 3×12 | 3 × 12 min at 100 %, 6 min recovery |
| **VO2max** | VO2max 5×3 | 5 × 3 min at 115 %, 3 min recovery |
| | VO2max 4×4 | 4 × 4 min at 110 %, 4 min recovery |

The three existing starters keep their exact steps so they stay recognisable.

- The domain gains `WorkoutCategory` (endurance, tempo, sweetSpot, overUnders, threshold,
  vo2max) and a static catalog (`WorkoutLibrary.classics(ftp:)` returning category + plan).
  The category belongs to the catalog entry, not to `TrainingPlan`, so recordings and
  archives don't change schema.
- Targets are rounded to whole watts, as now, and later to the trainer increment.
- A shared fixture (`contracts/fixtures/workout-library-250w.json`) lists every resolved
  step at 250 W FTP, so the Swift and JavaScript catalogs can't drift.
- Workout detail sheet: full profile chart, steps, intensity label, Start (→ pre-flight).
  Imported and Intervals workouts use the same sheet, plus Remove in its menu.

## 6. Story (optional)

- **Off by default**, toggled in Settings → Story. This replaces the toggles currently in
  Train and City. The existing `cyclepunkEnabled` preference is the source of truth.
- When enabled:
  - A **Story tab** appears: hero scene (existing `CitySceneView`), chapter title,
    progress in riding minutes, the next unlock ("5 minutes to the workshop lights"), and
    transmissions as a message log with locked ones as quiet placeholders.
  - A small **Home card**: chapter, progress bar, next unlock, opens the tab.
  - Pre-flight and result show the story rows described above.
  - Dialogue appears only outside the scored ramp (warm-up, cool-down, workouts) and never
    covers errors, controls or metrics.
- When disabled: no tab, no card, no receipts, no XP accrual. Earned progress is kept and
  reappears when story is turned back on.

## 7. Progress and Settings

**Progress**
- FTP trend first, for the selected rider. Real results only by default; a filter menu
  shows debug results. One colour per rider and one marker shape for real/debug, with a
  single combined legend.
- Activity list with filter chips: All · FTP tests · Workouts · Free rides. Rows use date
  and activity as the title, a result value, and badges (Debug, Uploaded, Interrupted).
  No inline trash buttons: delete moves to swipe, the context menu and the detail menu.
- Detail: the result chart from §4.4, sources, adopt, export, upload, delete.

**Settings**, grouped and short, with one-line footers and "Learn more" sheets:
Riders · Devices & trainer control (power matching, diagnostics) · Ride display (theme,
extra-large numbers, pixel ride) · Story (enable, explanation) · Intervals.icu · Backup &
transfer · About (version, credits, debug unlock).

## 8. Design system and code structure

**Components** in `App/DesignSystem/`: `MetricTile`, `PrimaryActionBar` (full-width,
pinned), `HoldToConfirmButton`, `PhaseTimeline`, `StepCountdownRing`, `StatusPill`,
`RiderChip`, `DevicesPill`, `WorkoutProfileChart`, `WorkoutCard`, `ResultPowerChart`
(best-minute highlight), and `SelectionRow` (replaces `SelectionMenu` and shows its value on
Mac and iPhone). **Tokens**: the existing accent/warning/danger palette, plus a type scale
(hero numbers, metric, label, body, footnote) and spacing scale. Keep the tested contrast
pairs.

**Platform shells**: `TabView` on iPhone; `NavigationSplitView` with a sidebar on Mac.

**Model split** (incremental, behind the existing tests): `AppModel` (757 lines) becomes a
coordinator over `RiderStore`, `DeviceHub` (wraps `BluetoothDevices`), `RideSetup`
(defaults, protocol recommendation, start blockers), `RideSession` (engine, commands,
stop/pause), `WorkoutCatalog` (library, Intervals cache, imports) and `StoryProgress`.
Presentation rules become pure functions in the domain module, so they can be unit tested
and mirrored in JavaScript: start-blocker reason, protocol recommendation, retest age
(8 weeks), cadence guard, result delta, today's workouts, re-targeted workout example.
Feature views move into `App/Features/{Home,Preflight,Ride,Result,Progress,Story,
Settings}/`; update `Tools/generate_project.py` accordingly.

## 9. Verification workflow

Every phase must pass the following before it counts as done. Visual review (launching
the app for inspection, screenshots, the preview walkthrough, simulator UI) still needs the
user's explicit permission each time (AGENTS.md).

1. **Scenario fixtures.** `--scenario <name>` seeds the in-memory preview store and UI
   state: `first-launch`, `home-today` (Intervals workout scheduled today),
   `home-not-connected`, `home-no-ftp`, `home-retest-due`, `library`, `preflight-blocked`,
   `ride-warmup`, `ride-ramp`, `ride-ramp-low-cadence`, `ride-cooldown`, `result-new-ftp`,
   `result-interrupted`, `workout-running`, `workout-paused`, `free-ride`, `resistance`,
   `story-off`, `story-mid`, `story-complete`, `progress-two-riders`. Mock rides earn no
   XP, so story states are seeded fixtures, never real grants.
2. **Screenshot matrix.** Extend `PreviewWalkthrough` to iterate scenarios × light/dark ×
   default/accessibility text size at 393 × 852 (iPhone 15 Pro), plus the Mac window. Add
   the same scenarios to `Tools/run_simulator.sh` for iOS simulator screenshots. Home,
   library, workouts and story are included, not just the test.
3. **Unit tests** for the presentation rules in §8, the library catalog against the shared
   fixture, `scheduledDate` decoding (present, absent, legacy archives), story on/off
   effects (no XP, no tab state when off), story ordering (training result before rewards),
   dialogue suppression during the ramp, the 72 % default for new tests, and 75 % legacy
   recordings still displaying correctly.
4. **UI smoke tests** (new XCUITest target, iOS simulator, mock sensors):
   - FTP test: Home → FTP test → pre-flight → start → skip warm-up (debug) → hold to finish
     → adopt → the Home library shows new targets.
   - Workout: library card → pre-flight → start → pause → resume → stop.
   - Free ERG: ±10 W → stop.
   - Story: enable in Settings → tab and Home card appear; seeded receipt after result.
5. **Accessibility pass**: VoiceOver order and actions on the cockpit (including the hold
   action), largest Dynamic Type, Increase Contrast, Reduce Motion, Mac keyboard use.
6. **Web**: shared fixtures for the presentation rules and library, plus existing suites.

Hardware checks (trainer response, step timing on real firmware) stay deferred and are
reported as not run.

## 10. Phases

| Phase | Scope | Exit gate |
| --- | --- | --- |
| **0 · Quick fixes** | Mac menu values, "Back to Train" label, History legend, Train FTP field coupling, live-ride bar only while riding | Existing tests pass |
| **1 · Foundations** | Scenario fixtures and walkthrough/simulator hooks (§9.1–2), design system components, model split, new shell (Home/Progress/Story/Settings), rider chip, Devices sheet, basic Home with FTP card and quick rides | All current flows reachable in the new shell |
| **2 · FTP test** | Shared pre-flight, cockpit (hold to finish, step/ramp time, cadence guard), result with adoption and training/story hand-off; factor picker removed; 8-week retest prompt | FTP unit tests and smoke test written |
| **3 · Home & workouts** | Today card, `scheduledDate`, auto-refresh, classic library and fixture, workout cards/detail, quick rides, workout/free-ride cockpit | Library fixture and workout smoke tests |
| **4 · Progress** | Trend, filters, rows, detail chart | Deletion and two-rider tests |
| **5 · Story** | Settings toggle, conditional tab and Home card, in-ride rules, receipts | Story on/off, ordering and suppression tests |
| **6 · Settings and polish** | Grouping, copy, accessibility pass | §9.5 checklist complete |
| **Web** | Port each phase after its native exit gate, one phase behind | Shared fixtures and web suites pass |

The Miyoo companion stays last; its button map (Finish ramp separate from Stop, no ramp
pause) already matches this plan.

## 11. Implementation status

Updated as phases complete.

### Phase 0 · Quick fixes (2 November 2026)

- `SelectionMenu` replaced by `SelectionRow` (`App/DesignSystem/`): a labelled native menu
  picker, so the selected value shows on Mac and iPhone.
- Ride header: "Minimise ride" while a ride is active; "Back to FTP Test"/"Back to Train"
  after it ends, chosen by activity.
- Chart: `TrendChart` has one colour per rider (stable across the rider filter), one marker
  shape for real (circle) and debug (diamond), and a single combined legend.
- Train: the free-text FTP field is gone; Train shows the FTP read-only with an explicit
  "Edit rider and FTP…" action, so it can no longer switch FTP Test setup to manual.
- The bottom live-ride bar appears only while a ride is active.
- `Tools/generate_project.py` now includes `App/**/*.swift` recursively.
- Verified: `swift test` 90/90, iOS Simulator and Mac builds succeed. Not verified visually.

### Phase 1 · Foundations (2 November 2026)

- **Scenarios.** `--scenario <name>` (and `--scenario-matrix`) with all 21 names from §9.1, in
  `App/Preview/PreviewScenarios.swift`. They are honoured only with `--debug-preview`, call
  `AppModel.resetPreview`, and `LocalStore.eraseAllForPreview` refuses a persistent store (tested).
  Story states are seeded recordings, never mock-ride XP. `PreviewWalkthrough` now captures
  scenarios × dark/light × default/accessibility text × a 393 × 852 phone layout, plus the Mac
  window; `Tools/run_simulator.sh --matrix [dir] [scenario…]` does the same through `simctl`.
  Written, not run.
- **Design system** (`App/DesignSystem/`): `SelectionRow`, `MetricTile`, `PrimaryActionBar`,
  `HoldToConfirmButton`, `PhaseTimelineView`, `StepCountdownRing`, `StatusPill`, `RiderChip`,
  `DevicesPill`, `WorkoutProfileChart`, `WorkoutCard`, `ResultPowerChart`, plus type/spacing tokens.
- **Shell.** `TabView` on iPhone, `NavigationSplitView` on Mac, Home / Progress / Story (only when
  enabled) / Settings. The cockpit replaces the shell while a ride is shown; minimising it leaves
  the live-ride bar above the tabs. Rider chip and Devices pill sit on Home's toolbar and open the
  rider sheet and the shared Devices sheet. Home has the FTP card and quick rides; the FTP test,
  free ERG, resistance and workout library are still the Phase 0 forms, pushed from Home.
- **Rules in `FTPunkDomain`** with tests: start blocker, protocol recommendation, 8-week retest,
  result delta, cadence guard, hold-to-finish timing, phase timeline, device summary, rider
  initials, workout profile and result chart model.
- **Model split, incremental.** `AppModel+Presentation.swift` carries the readiness/device/FTP
  summaries and preview reset; readiness rules are now pure domain code. `RideSetup`, `RideSession`,
  `WorkoutCatalog` and `StoryProgress` extractions follow with their phases; the ride engine and
  trainer-command code in `AppModel` is untouched.
- Test change: `nativeWorkoutWorkflowSavesWithoutChangingFTP` now asserts `cockpitPresented`
  instead of the removed `selectedTab == 1`.
- Verified: `swift test` 111/111, iOS Simulator and Mac builds succeed. Not verified visually.

### Phase 2 · FTP test (2 November 2026)

- **Pre-flight** (`Features/Preflight/PreflightView.swift`): one checklist for FTP test, free ERG
  and resistance rides, with Start always visible and the blocker reason directly above it.
  Rider, Devices (with the cadence line), Story row (only when enabled), Protocol (recommended
  ramp and its reason; Change opens the three protocol cards and "Which protocol, and why?"),
  Warm-up/cool-down behind an Adjust disclosure, a fixed "72 % of your best minute" estimate row,
  Pixel ride, and a Debug group visible only with mock sensors. The old three-page setup form and
  its factor picker are gone.
- **Cockpit** (`Features/Ride/FTPCockpitView.swift`): minimise control, phase timeline, large
  target/actual tiles, "Step N" and ramp time, a draining next-step ring, heart rate, cadence with
  the amber "Ramp ends below 45 rpm" guard below 60 rpm, MAX 60 S, a compact Stelvio strip, and a
  bottom bar with **Hold to finish** (1.5 s ring, VoiceOver action, ⌘⇧F on Mac) beside a one-tap
  **Stop & save**. Cool-down shows the provisional result. Debug controls moved to a sheet.
  Automatic finish (cadence below 45 rpm for 5 s) and all scoring are untouched.
- **Result** (`Features/Result/ResultView.swift`): estimate with change from the current FTP,
  "72 % of your best minute", the power chart with the best minute shaded and labelled, "How this
  is calculated" (72–77 % range), a pinned "Use 209 W as Alex’s FTP" / "Keep 250 W" bar, inline
  confirmation, a training hand-off ("Library workouts now use 209 W", with a Sweet spot 3×10
  example), story receipt with a non-scoring calibration log line, upload (existing consent sheet)
  and Done. Interrupted and debug results use the same layout; debug results cannot be adopted.
- **Rules/tests**: new domain rules for result order, interruption summary, adoption detection,
  cadence status, durations and averages; the classic workout catalog was pulled forward from
  Phase 3 so the hand-off example comes from it. New tests cover 72 % for new tests, 75 % legacy
  recordings and archives, the unchanged automatic finish, the recommendation, adoption and
  retargeting. `FTPunkUITests` (XCUITest) target added through the generator; the FTP smoke tests
  are written and compile.
- 8-week retest prompt is on Home's FTP card (Phase 1) and tested.
- Deviation: the smoke test cannot adopt a mock-sensor result (debug results never become FTP), so
  it is split into a debug ride to the result and a seeded `result-new-ftp` adoption.
- Verified: `swift test` 133/133, iOS and Mac builds succeed, `build-for-testing` succeeds for the
  UI tests. UI tests not run; no visual review.

### Phase 3 · Home and workouts (2 November 2026)

- **Library** (`Sources/FTPunkDomain/WorkoutLibrary.swift`): `WorkoutCategory` and 14 classic
  workouts exactly as tabulated in §5, held as percentages of FTP with the category on the catalog
  entry, not on `TrainingPlan`. 10 min 50 → 70 % warm-up ramp, 5 min 60 → 40 % cool-down ramp,
  recoveries at 50 % between efforts; the three original starters keep their exact steps (tested
  against `TrainingPlan.starters`). Targets are whole watts. A new FTP re-resolves cards when they
  are shown; the plan is snapshotted when a ride starts. `contracts/fixtures/workout-library-250w.json`
  is generated from the catalog and checked by a test; an independent script re-derived every
  number from the plan table.
- **Home** is a ride picker: Today (Intervals.icu workouts scheduled for today, else "Nothing
  planned today" with the next one, else a dismissible hint), FTP card (above Today with no FTP),
  quick rides, the library with category chips, Upcoming (next 14 days, with Refresh and pull to
  refresh), and My workouts with a "+" menu for import and the example JSON. Cards show name,
  computed duration and a profile; with no FTP they say "Needs FTP". The detail sheet shows the
  profile, steps, intensity label and FTP used, with Start and (for imported/Intervals workouts)
  Remove. Onboarding appears for a first launch with no rider data.
- **`scheduledDate`**: optional local `yyyy-MM-dd` on `CachedWorkout`, decoded as optional and
  taken from `start_date_local`. Older caches and v3 archives load unchanged (tested against the
  shared v3 fixture); validation rejects impossible dates; `contracts/README.md` and the v3 schema
  document it, no archive version bump. Calendar entries inside the downloaded window that the
  server no longer returns are pruned so removed events do not linger as phantom workouts.
- **Sync**: Home refreshes when it appears if the last download is over an hour old
  (`SyncPolicy`), never during a ride, and quietly (status text instead of an alert). Previews
  never touch the network.
- **Workout pre-flight and cockpit**: pre-flight rows for profile, duration, FTP used (and a
  warning when a fixed-watts workout was saved at another FTP), intensity 50–150 % and a trainer
  range check; the cockpit shows step name and time left, next-step preview, the profile with a
  progress marker, ±5 % intensity, and Pause/Resume as primary with one-tap Stop. Free ERG shows
  ±10 W and resistance ± level in the same cockpit.
- **Model split**: `WorkoutCatalog` now owns the cached library, imports, Intervals refresh state
  and download; `AppModel` keeps thin forwarding members so existing callers and tests are unchanged.
- Tests: fixture, `scheduledDate` (present/absent/legacy), today/upcoming/mine/prune rules, sync
  policy, classic workouts running through the app model, onboarding, story-off effects. UI smoke
  tests for the workout and free ERG flows are written and compile.
- Verified: `swift test` 150/150, iOS and Mac builds and `build-for-testing` succeed. UI tests not
  run; no visual review.

### Phase 4 · Progress (2 November 2026)

- **Progress** replaces History. The FTP trend is first, for the selected rider (default: the
  rider chip's rider; a filter menu offers All riders or another rider). Real results only by
  default; the same menu shows debug results. One colour per rider (stable across the filter),
  circles for real and diamonds for debug, one combined legend.
- **Activity list** with filter chips All · FTP tests · Workouts · Free rides. A row is date and
  activity, a result value (FTP, or duration) and badges (Debug, Uploaded, Upload queued, Upload
  needs attention, Interrupted). The inline trash buttons are gone: delete is swipe, the context
  menu and the detail menu, always with the existing confirmation. A running ride's recording
  cannot be deleted.
- **Detail** (`ActivityDetailView`): the FTP result card, the result chart with the best minute
  shaded, "How this is calculated", adopt (or "set from this test"), story receipt only while the
  story is on, sources, export, upload, and delete in the menu. Recordings made with 75 % show
  their own factor.
- Rules in `FTPunkDomain` (`ProgressRules`, `ActivityFilter`, `ActivityRowModel`, `TrendMetric`) with
  tests; two-rider, filter, deletion (samples, pending upload, other riders, adopted FTP kept) and
  running-ride tests. A UI smoke test for rider filtering and swipe deletion is written and compiles.
- Verified: `swift test` 156/156, iOS and Mac builds and `build-for-testing` succeed. UI tests not run; no visual review.

### Phase 5 · Story (2 November 2026)

- **Settings → Story** holds the toggle (the existing `cyclepunkEnabled` preference stays the
  source of truth; the toggles in Train and City are gone). Off by default.
- **On**: a Story tab (Lowline scene, "Chapter 1 · Last Light", progress in riding minutes, the next
  unlock in plain words such as "5 minutes to the workshop lights", transmissions as a message log
  with locked ones as quiet placeholders) and a small Home card with progress and the next unlock.
  The pre-flight shows "Earns Lowline progress" (and "stays quiet during the ramp" for tests).
  The result shows the story receipt after the training result and hand-off, with a non-scoring
  calibration log line that grants nothing.
- **Off**: no tab, no Home card, no receipts (also hidden in Progress details), no in-ride line, and
  no XP accrual, because new sessions record `adventureEnabled = false`. Earned progress is kept
  and reappears when the story is turned back on. Turning it off while on the Story tab returns to Home.
- **In ride**: `StoryDialogue` allows a single quiet line only in warm-up, cool-down and workouts,
  never in the scored ramp, never for mock rides, and the cockpit hides it while an error, a trainer
  transition or the stop confirmation is showing. Story never changes trainer targets (tested by
  running the same workout with the story on and off) and rewards riding time only.
- `result-new-ftp` now has the story on, so the matrix shows the receipt order. UI smoke tests for
  enabling the story and the receipt order are written and compile.
- Verified: `swift test` 162/162 at this point (final totals in Phase 6); iOS, Mac and `build-for-testing` succeed.

### Phase 6 · Settings and polish (2 November 2026)

- **Settings** are grouped as planned: Riders, Devices & trainer control (Devices sheet, power
  matching), Ride display (theme, extra-large numbers, pixel ride), Story, Intervals.icu, Backup &
  transfer, a Debug group that exists only after the About unlock, and About (version, credits,
  protocol and estimate explanations, debug unlock). Each group has one line of footer text and
  "Learn more" sheets for power matching, the story, Intervals.icu, riders and local data.
- **Copy** updated for the new flow (power-matching prompt, estimate explanation, 72 % only).
- **Mac keyboard**: ⌘. Stop & save, ⇧⌘F finish ramp, ⇧⌘P pause/resume in the workout cockpit.
- **Chips** share `FilterChip` (selected trait, Increase Contrast outline); Home section titles are
  headers for VoiceOver; card titles stop truncating at accessibility text sizes; Home scrolling
  respects Reduce Motion.
- **README, contracts, UX review and evolution plan** updated for navigation, setup, estimate,
  story, library and scenarios; CI also compiles the UI tests.

**§9.5 accessibility checklist, status.** Done in code and covered by unit tests where possible;
everything that needs eyes, a screen reader or a keyboard on a real window is *not yet verified*.

| Item | State |
| --- | --- |
| VoiceOver order and actions on the cockpit | Order follows reading order (header, timeline, banners, target/actual, ring, supporting tiles, story line, actions); tiles are single elements with value text; Hold to finish has the custom action "Finish ramp now" and a hint; phase changes are announced. Not exercised with VoiceOver. |
| Largest Dynamic Type | Tile rows, action bars, the live-ride bar and chips restack at accessibility sizes; numbers scale and shrink to fit. The scenario matrix has an accessibility-size pass. Not looked at. |
| Increase Contrast | Cards, chips and the hold button add outlines; rider colours and primary pairs are contrast-tested. Not looked at. |
| Reduce Motion | The next-step ring, Stelvio and Home scrolling do not animate; the hold ring is a determinate progress indicator and keeps filling. |
| Mac keyboard | Shortcuts above; sidebar and controls use standard focusable SwiftUI controls. Not exercised. |

Other open points: hardware checks (trainer response, step timing on real firmware) stay deferred;
the web port is not started (see Deviations); the model split is incremental (below).

### Deviations and decisions

- **Model split** is partial: `WorkoutCatalog` and the presentation/preview extension are real
  extractions; `RiderStore`, `DeviceHub`, `RideSetup`, `RideSession` and `StoryProgress` remain in
  `AppModel` (their rules are pure domain code). The ride engine, trainer commands and ownership
  code were not touched, to protect the safety invariants.
- **Classic library** was pulled into Phase 2 so the result's hand-off example comes from it.
- **Recoveries** in the new workouts sit between efforts, not after the last one, because the
  cool-down ramp follows; the three original starters keep their exact steps.
- **Smoke test adoption** uses a seeded real result because mock results can never be adopted.
- **Web port** (`ftpunk_web/`) is untouched: no JavaScript runtime is installed. The shared fixture
  `contracts/fixtures/workout-library-250w.json` and `scheduledDate` notes are ready for it.
- **`result-new-ftp`** has the story enabled so the screenshot matrix shows the receipt order.
- **Calendar pruning**: entries inside the downloaded window that the server no longer returns are
  removed from the cache (not in the plan; it stops removed events lingering as phantom workouts).

### Final verification (2 November 2026)

- `swift test`: 165 tests passed (90 existing + 75 new; one existing assertion changed, see Phase 1).
- `xcodebuild … -scheme FTPunk -sdk iphonesimulator … build`: succeeded. `-scheme FTPunkMac … build`:
  succeeded. `-scheme FTPunk … build-for-testing` (generic simulator and the iPhone 17 simulator
  id): `** TEST BUILD SUCCEEDED **`. `swift build -c release`: succeeded.
- Not run: the XCUITests, the screenshot matrix, the preview walkthrough, any simulator or app
  launch, VoiceOver, Increase Contrast, physical trainer, iPhone or Miyoo checks, the web port.

### Review fixes, 2 November 2026

Fixes from the first visual review (Mac preview and simulator matrix), made without opening the app.

- **UI tests could not find the app.** `xcodebuild test` failed with "The bundle identifier for FTPunk couldn't be
  read … Debug-iphonesimulator/FTPunk" (no `.app`). The iOS target and the Swift package's executable product were both
  called `FTPunk` (`xcodebuild -list` shows two `FTPunk` schemes), and the UI-test target found its app by that name.
  `Tools/generate_project.py` now names the iOS target `FTPunkiOS` (scheme `FTPunk`, product `FTPunk.app`, bundle id
  `com.kainkordian.ftpunk` and the README commands are unchanged), points `TEST_TARGET_NAME` at it and records
  `TestTargetID` for the UI-test target. `build-for-testing` still writes an `.xctestrun` whose `UITargetAppPath` is
  `…/Debug-iphonesimulator/FTPunk.app`. The tests themselves were not run, so the fix is unconfirmed until someone runs them.
- **Result chart** (FTP result and activity detail): phase names are drawn in an overlay, in a top row inside the plot,
  each no wider than its own band (short form, or nothing, for narrow bands); "Best minute 290 W" sits in a second row,
  clamped inside the plot, so nothing touches the axis labels. The power line is the app accent (dark green on light,
  lime on dark; tested ≥ 3:1 against the plot and its tints) instead of the default series colour.
- **`ride-ramp-low-cadence`** seeds power at the current step target (tested within 25 W), not 220 W against 115 W.
- **Screenshot matrix**: the first launch after an appearance or text-size change waits 9 s (others 4 s), and a PNG under
  `FTPUNK_MIN_SCREENSHOT_BYTES` (150 000) is retaken up to three times, then reported. The app waits 250 ms before applying a
  scenario so the first frame is on screen before the 1.3 s two-rider seeding blocks the main actor. Progress itself has no
  state that can leave it blank (it renders from `model.history`, which is loaded before the tab is selected).
- **Home**: the FTP test appears once (the FTP card button; Quick ride is Free ERG and Resistance). The FTP card has one
  status line, "Tested 12 Oct · 3 weeks ago", which becomes "… · 9 weeks ago · time to retest?" in the warning colour after
  8 weeks. The rider chip shows the name next to the initial (cut at 14 characters, fixed size so the toolbar cannot collapse it).
- **Workout profiles** use one scale, 0–130 % of FTP (clamped above), with zone colours: recovery < 56 %, endurance 56–75,
  tempo 76–87, sweet spot 88–94, threshold 95–105, VO2max > 105. Colours climb in lightness with intensity and keep 3:1
  in both themes (tested); plans without an FTP stay neutral. Card captions use minutes below 120 min ("60 min · main
  170 W"), "2 h 15 min" above.
- **FTP cockpit**: Stop & save is an outline in every phase; the extra warm-up progress bar is gone; the coaching line is
  dropped mid-ramp and at accessibility sizes, and the scroll content has a bottom margin. At accessibility sizes the header
  is phase + time only, the phase timeline loses its labels, and Target, Actual and the supporting readings are single-line
  rows. **Not changed (scope):** the Stelvio placement and sizing; the visualisation is being redesigned separately.
- **Actions that looked like labels**: "Keep 250 W" and onboarding's "Not sure of my FTP: take the FTP test" use the
  outline secondary style, "Skip for now" a new tinted tertiary style (44 pt, full width). The secondary style now dims when disabled.
- **Pre-flight devices line**: "Trainer: not connected · Power: from trainer · Heart rate: none".
- Tests: `swift test` 180 passed (165 + 15 new: label overlap and clamping, zones, fixed scale, ramps, palette contrast
  and lightness steps, durations, FTP status line, chip name, devices line, cockpit layout, line contrast; the low-cadence
  scenario assertion was added to an existing test). Builds: iOS Simulator, Mac and `build-for-testing` succeed.
- **Not verified**: the UI tests, the matrix and any screenshot, how the chart labels, profile colours, rider chip and
  accessibility-size cockpit actually look (including whether both readings fit an iPhone 15 Pro at the largest sizes),
  VoiceOver, and the black-capture fix (a timing change, not reproduced).
