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
