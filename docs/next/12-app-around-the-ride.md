# 12 · The app around the ride: Home, summary, Progress, Settings

Owner-requested plan (2026-11-12, revised 2026-11-13). **Designs:**
`design/app-redesign/4-home.html`, `5-ride-summary.html` and `6-settings.html` (static HTML,
1470×920; read their inline sizes and colours). Runs after plan 11 (it reuses the Tektur font
and the tokens from plan 11 steps 1 and 3). Presentation only: no change to ride logic, storage formats, the archive
contract, uploads or the 72 % estimate.

## Fidelity: build what the mockups show

The owner signed off the mockups (2026-11-13). The app must match them as closely as SwiftUI
allows; they are not inspiration. For every screen in this plan:

- Take layout, order, sizes, spacing, radii, colours, weights, wording and capitalisation from
  the HTML (`design/app-redesign/*.html`; every value is an inline pixel value at 1470×920)
  and check against the rendered reference (`design/app-redesign/png/*.png`).
- Do not add, drop, rename or move an element, and do not substitute system controls or
  styles where the mockup draws its own (pills, steppers, switches, segmented controls).
  Icons: the SF Symbol closest to the drawn one.
- If something cannot be built as drawn (platform limit, accessibility, a state the mockup
  does not show), choose the nearest solution in the same style and list it under
  "Deviations from the mockup" in the wrap-up report. Never deviate silently.
- States the mockups do not draw (paused, no signal, amber and red cadence, light theme,
  iPhone) follow this plan's text and reuse the drawn parts.
- Each mockup gets a preview scenario seeded with the mockup's sample values (same numbers,
  names and times). At the end, ask the owner once for permission to capture those scenarios
  at 1470×920 (AGENTS.md), put each capture next to its PNG and fix visible differences in
  position (more than about 4 pt), size, colour or text before reporting done.

## Goal

One coherent, complete look for the whole app (the filled-tile look and Tektur font of the ride dashboard), screens that
use a full-screen window instead of a 760 pt column, and every action looking like an action.
Light and dark both stay supported outside the ride screen; the canvas shows dark only, so each
new colour needs a light partner that passes the existing contrast tests.

## Steps

1. **Tokens for the whole app** (`App/DesignSystem/Tokens.swift`, `App/Theme.swift`):
   radius scale (control 14, card 24, tile 32, pill), three surfaces (ground, card, raised) as
   light/dark pairs, all text through the `Font.ftp` helper (so the font setting from plan 11 applies everywhere), one button family as pills (primary lime, secondary filled, tertiary text,
   destructive), a visible text-field style (filled field, placeholder, focus ring), a
   `SettingRow` (title, one-line explanation, control on the right). `ftpCard` loses its
   outline except under Increase Contrast. Replace `Chaindance.*` colours outside
   `Features/Ride/RideVisual*` with these tokens.
2. **Shell** (`Features/Shell`): the sidebar gets the wordmark, the three sections, a
   **Devices card** at the bottom (trainer, power meter, heart rate with state text, a Connect
   button that opens `DevicesSheet`, and a "Mock sensors" badge when mock mode is on) and the
   **rider chip** below it. The rider chip and Devices pill leave Home's toolbar on Mac; the
   rider is still chosen in one place only. iPhone keeps tabs and the toolbar items.
3. **Home** (`Features/Home`): from 1100 pt width, two columns.
   - Left: a **Next up** card (today's workout with Start; otherwise the next planned one with
     its date and "Ride it today", plus "Steps and details"), then the library with the filter
     chips, a "Mine" chip for the rider's own workouts, and "New workout" and an "Import…" menu
     (file, paste as text, example JSON) in the section header. The separate "My workouts"
     block and its explanatory paragraph go.
   - Right: the FTP card (value, W/kg, age or retest prompt, "Take the FTP test"), Quick ride,
     and **Coming up** as a compact list (date, name, duration) with Refresh and the one-line
     sync summary from plan 10 ("7 cycling workouts with % FTP targets synced").
   - Below 1100 pt and on iPhone: one column in today's order. With no FTP, the FTP card
     still moves to the top.
4. **Sheets:**
   - `RiderSheet`: real text fields with placeholders ("Name", "FTP in watts"), "Add rider" and
     "Save FTP" as buttons, disabled until the field is valid.
   - `DevicesSheet`: scanning happens inside the row (it expands, shows "Searching…" with a
     spinner, then the found devices, then a hint with "Scan again" if nothing is found after
     the timeout). No sheet on top of a sheet.
   - `WorkoutDetailSheet`: at least 720×640 on Mac and resizable, so a seven-step workout shows
     without scrolling; title aligned with the content.
5. **Ride summary** (`Features/Result`, `Features/Progress/ActivityDetailView`, `RideCharts`,
   `ResultPowerChart`): one `RideSummaryView` for the result screen and the activity detail.
   - Header: activity name as the title (not only the date), date and rider below, upload state
     as a chip; Export FIT, Other formats and Done as buttons on the right ("Upload again…"
     inside the upload chip's menu).
   - Hero card: FTP test → estimate, W/kg, **change against the current FTP**, "72 % of your
     best minute", the pinned "Use … / Keep …" pair (same rules as today, debug results still
     cannot be adopted); other rides → "Ride saved", name, time.
   - The figures grid comes **before** the charts (time, best minute or average power,
     normalized power, heart rate average and max, cadence, work, then the rest).
   - **One main chart**: power, target (dashed) and heart rate on two axes, best minute shaded,
     x-axis in m:ss. The trainer's power, when a meter was the source, is a thin cyan line
     (lime on amber could not be told apart). One legend; the duplicate legend row goes.
   - All charts of one ride share one time domain (today DFA α1 and pedal balance use their
     own; in a 2.6 min ride the balance chart spanned 0–1 min). Pass the domain in.
   - The hover reading goes into a fixed line above the chart instead of a card over the
     heart-rate chart.
   - Heart-rate variability, pedal balance (fix the "L 56 / R 56" label colliding with the
     legend) and "How the estimate is calculated" become three disclosure rows under the chart.
   - Steps table: step name, m:ss, target W (today: "Step 1 · 600 s · 147 W"). Add the
     average heart rate and average power ridden per step (`StepHeartRate` from plan 11, `RideSummary`, with tests).
6. **Progress** (`Features/Progress`): same maximum width and card style as Home. The FTP trend
   also plots manual and Intervals.icu-synced FTP values as hollow markers, so a rider without
   a test sees a line (decision 3). Activity rows show the duration once and a type icon.
   Debug rides are hidden in the list unless the filter menu shows them, as in the trend.
7. **Settings** (`Features/Settings`): on Mac a section list (Riders, Devices and trainer
   control, Ride screen, Intervals.icu, Backup and transfer, About and help) beside one
   detail pane of grouped cards built from `SettingRow`; on iPhone the same sections as a
   `Form` with links. Actions are buttons ("Sync now", "Prepare portable backup"), "Disconnect"
   is destructive, set apart and asks once. The four "Learn more" rows become one
   "About and help" section. The connected state shows as a dot in the section list.
   Appearance gains **Font: Tektur / SF Rounded / System** (`appFont`) above Theme.
   Carry-over from the plan 11 recheck (owner approved deferral, 2026-11-14): replace the
   Chaindance layout system pop-up with the shared pill choices and add its row description.
8. **Pre-flight** (`Features/Preflight`): tokens only. The devices row uses the same state
   texts as the sidebar card.
9. **Preview scenarios and wrap-up:** refresh the Home, result, Progress and Settings scenarios
   for a 1470×923 window, README screenshots text, roadmap, move this file to `docs/archive/`.

## Decided

- Font Tektur; this plan and plan 11 replace `docs/next/macos-chaindance-design.md`
  (move it to `docs/archive/` as superseded when plan 11 starts).
- Progress plots manual and synced FTP values (the owner has no preference; it avoids an
  empty chart).
- The steps table shows the average heart rate per step, matching the ride screen's strip.

## Still open (ask the owner if it matters while building)

- The rider chip and devices move into the sidebar on Mac.

## Done

`swift test` passes and both CI builds pass; VoiceOver labels and accessibility identifiers
are unchanged (the XCUITests still find them). Then ask the owner for the visual review in
light and dark.

## Not in this plan

iPhone-specific redesign beyond the shared tokens, the web app, the workout builder,
backup and import screens (tokens only).

## Implementation checkpoint (2026-11-14)

Plan 11 was committed and pushed as `b618ac8` before this implementation began. Plan 12
adds the shared font/surface/action/field/setting-row styles, Mac sidebar and wide Home,
inline device scanning, larger workout detail sheet, common result/history summary,
combined chart and fixed hover line, chronological manual/synced/ramp FTP trend, hidden
debug activities, and the Settings section/detail layout. Existing model actions still own
adoption, upload consent, re-upload, export and rider changes. No archive/storage format,
upload transport, trainer protocol, ramp scoring or estimate-factor change was made.

Pure presentation rules and tests cover per-step averages excluding pauses, the common
chart time domain, merged FTP settings/results, debug filtering and the reference scenarios.
The four new isolated scenarios are `app-home`, `app-summary`, `app-progress`, `app-settings`;
their Mac walkthrough size is 1470×923. The summary fixture keeps 290 W best minute,
72 % / 209 W estimate, current FTP 250 W and recorded weight 82.2 kg; its illustrative
summary totals use preview-only display fixtures as in plan 11.

### Deviations from the mockup

- Calendar dates and relative ages follow the actual preview date; the reference's weekday,
  calendar-date and relative-age examples are internally inconsistent. Names, powers and
  durations use the reference data and the existing classic workout definitions.
- Native navigation bars, menus and system save/confirmation dialogs retain platform
  typography. App content uses the font helper; the workout text editor retains a
  monospaced face for editing structured text. Chaindance art is unchanged.
- Settings panes not drawn in the reference retain their existing content within the new
  grouped-card shell. The drawn Ride screen uses the shared SettingRow and pill/switch parts.
- On compact widths the summary stacks, legends can scroll horizontally, the fixed reading line scales/truncates to fit, and
  adoption stays pinned. Per-step details and source metadata follow below the reference's
  first-screen content.

The owner performs visual review. No native app/browser was opened for inspection and no
agent capture was made. Visual fidelity in light/dark, native save/dialog behaviour, inline
Bluetooth scanning on hardware, and VoiceOver execution remain unverified. This plan stays
in `next/` until the owner reviews the implementation. Verified: 387 Swift tests, both CI
builds and `git diff --check` pass. Rebuilt `dist/FTPunk.app` while stopped and verified its
bundle signature. The owner subsequently authorized committing and pushing Plan 12 on 2026-11-15; visual recheck remains pending.


### Owner review corrections 21–27 (2026-11-15)

The owner reviewed light theme in a normal, titled Mac window on a large display and
confirmed that hover readings occupy a fixed line above the summary chart. Corrections:

- Shell and summary respect the top safe area and normal title bar; full-size title-bar
  extension stays specific to the ride dashboard. The sidebar and first cards retain their
  own top padding below the title bar.
- Segments have paired light/dark tracks and labels; off switches use the adaptive raised
  surface and text colour. Label/thumb contrast is covered by tests. Coming up's Refresh
  uses the shared secondary pill style.
- Progress's first-ride state uses shared typography in a full-width activity card. The six
  featured workouts use three columns when the library has room, rather than four plus two.
- Summary chart geometry is cached by recording revision. One target-series construction
  and one sample traversal produce the three point arrays, limits and heart-rate transform;
  marks and both axes use stored values. The plot is an independent equatable view. Hover
  readings use a fixed-size overlay without a horizontal ScrollView, so changing their text
  contributes no intrinsic size to the card/chart layout.
- `app-summary-long` supplies a 3,240-second workout with 9,647 samples and 3,214 heart-rate
  points. Its regression test checks geometry, signal gaps, heart-rate projection, reuse
  across 1,000 unchanged updates, and invalidation when samples change.
- Live dashboard power reads only the recent 62-second sample window. Workout heart-rate
  points and per-step sums accumulate from appended samples; clock events (pause/resume/skip)
  or recording replacement cause a replay. Live summary totals are memoized by recording
  revision. Tests compare against the existing full-recording
  calculations, verify paused samples and stale signal, and count visits over a 54-minute ride.

Visual recheck of these corrections and real pointer/layout behaviour remain with the
owner. No native app was launched or captured by the agent. These performance tests cover
presentation data and cache reuse; they do not measure Swift Charts or native layout on screen.

Verified after these corrections: 392 Swift tests, both required iOS/Mac builds, and
`git diff --check` pass. On this machine the Debug long-ride geometry build took 8.84 ms;
including 3,214 HR projection checks and 1,000 cache-reuse updates took 15.30 ms. This is
nonvisual domain work, not an on-screen frame-time measurement. Rebuilt the stopped
`dist/FTPunk.app` and verified its signature and bundled font bytes. The owner authorized committing and pushing these changes on 2026-11-15.
