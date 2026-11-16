# 13 · Walkthrough fixes, Chaindance parked, steadier power matching

Owner-requested plan (2026-11-15), from the owner's nine points after riding with the plan 12
build and from the review of that ride's recording (Sweet spot 3×12 min at 90 %, FTP 245 W,
Suito + Assioma, 53:35). Mac at 1470×923 is the reference window; iPhone keeps working but is
not redesigned. No change to ramp scoring, the ramp protocol or the 72 % estimate, and **the
FTP test's trainer control stays exactly as it is** (step 9 explains how).

Steps 1–8 are independent of each other and of step 9. Step 4 (hover) should run before or
together with steps 2 and 3, which use it. Each step can be its own commit when the owner asks.

## Steps

1. **A visible way back from pre-flight.** Today the only way back to Home is the faint "‹"
   in the title bar; the sidebar's Home and Go › Home (⌘1) do nothing, because they only set
   `model.destination = .home` while `model.preflightPath` keeps the pre-flight on top
   (`App/Features/Shell/AppShell.swift:52`, `App/MacAppCommands.swift:24`,
   `App/Features/Home/HomeView.swift:17`).
   - Add one model action (next to the existing ones in `App/AppModel+Presentation.swift`) that
     sets `destination = .home` and empties `preflightPath`. The sidebar's Home and Go › Home
     call it, so choosing Home always shows the Home root. Progress and Settings are unchanged.
   - `PreflightView` gets a visible "‹ Home" control at the top left of its content (shared
     secondary pill, accessibility label "Back to Home") and Esc does the same
     (`.keyboardShortcut(.cancelAction)`). On Mac the window toolbar then stays hidden on
     pre-flight as well (`HomeView.swift:56`); iPhone keeps its navigation bar.
   - Test (the Home workflow tests): from a pre-flight path the action leaves an empty path on
     Home; it changes nothing while a ride is presented.
2. **Progress: activity rows.** On Mac each row is a `NavigationLink` drawn as a default
   bordered button 43 pt high (`App/Features/Progress/ProgressTabView.swift:127`), while its
   content is taller: the title sits above the grey bar and the uploaded / interrupted badge
   hangs below it, over the next row's title. Give the link `.buttonStyle(.plain)` and draw the
   row as a card in the app's style (`ftpCard`), tall enough for title, subtitle and badges,
   with the hover state from step 4 and the same spacing as other card lists. Swipe actions,
   the context menu, labels and identifiers stay. Seed the `app-progress` preview scenario with
   one row of each badge (uploaded, upload queued, upload failed, interrupted) so the review
   can see them.
3. **Coming up also shows the last 7 days.** Today the calendar download asks for today…+14
   days (`App/WorkoutCatalog.swift`, `download`) and `TodayWorkouts.upcoming` keeps only dates
   after today (`Sources/FTPunkDomain/HomeRules.swift`).
   - Download from today − 7 days to today + 14 days. The cache replacement of plan 10
     (`TodayWorkouts.stale`) keeps its rule: the rider/account's calendar cache is replaced by
     the qualified download, now for this 21-day window.
   - New pure function `TodayWorkouts.recent(_:riderID:today:)`: the rider's calendar workouts
     dated from today − 7 to yesterday, oldest first. Tests: window edges, other riders,
     undated entries excluded, today excluded. `select` and `upcoming` must give the same
     results as before (their tests stay unchanged); check every other reader of
     `model.workoutLibrary` so a past workout never shows as today's or as "Next up".
   - New pure function that says whether a past planned workout was ridden: a saved,
     non-debug ride of that rider on that local date whose workout name equals the plan's
     name. Tests for match, other day, other rider.
   - `UpcomingSection` (`App/Features/Home/WorkoutLibrarySection.swift`): the card title becomes
     "Calendar"; inside, a small caption "LAST 7 DAYS" with the past rows, then the caption
     "COMING UP · 14 DAYS" with the upcoming rows as they are now. Past rows are clearly different: date,
     name and duration all in the secondary colour, and a leading mark, a tick
     (`checkmark.circle.fill`, secondary) when ridden and an empty circle when not; future rows
     keep primary-colour names and get no mark. A past row still opens the workout detail
     sheet (it can be ridden today). With no past workouts the first caption and group are
     left out. The card must not grow the page at 1470×923: if both groups do not fit, the
     list scrolls inside the card and opens with the first coming-up row visible.
   - Seed `app-home` with three past workouts (one ridden) in addition to the upcoming ones.
4. **Hover highlight on everything clickable.** No tile has a hover state today; all of them
   use `.buttonStyle(.plain)` (25 uses in 15 files). Add one shared button style (or modifier)
   in `App/DesignSystem/`: on hover the fill moves to the raised surface of the tokens and
   cards get a 1.5 pt outline in the accent colour at 60 %; pressed is the hover look slightly
   dimmed; disabled controls never highlight; 0.12 s ease; no effect on touch. Light and dark
   pairs come from the existing tokens; with Increase Contrast the outline is full strength.
   Apply it to: workout cards (`WorkoutCard`), the Today / Next up cards, the FTP card's
   action, quick-ride tiles, calendar rows (step 3), filter chips, sidebar items, the devices
   card and the rider chip, activity rows (step 2), actionable pre-flight checklist rows,
   Settings section rows, and on the ride dashboard the Next tile (it skips the step) and the
   header buttons. Tiles that only show values must not react. Accessibility elements,
   labels and identifiers stay as they are (plan 10, step 1).
5. **Pre-flight shows the intervals.** The workout pre-flight shows only the title line and an
   80 pt profile without values (`App/Features/Preflight/PreflightView.swift`, `workoutRows`).
   Move the step table and the hoverable chart of `App/Features/Home/WorkoutDetailSheet.swift`
   (rows from `WorkoutPreview.steps(for:intensity:showValues:)`: name, duration, % FTP, watts;
   chart with `showsAxis` and `selectedStep`) into one shared view in `App/DesignSystem/` and
   use it in both places. In pre-flight it follows `model.preflightIntensity` live, so watts
   change with the intensity stepper while % FTP shows the scaled percentage, exactly as the
   detail sheet computes it. Without an FTP it shows durations only, as the sheet does. The
   start bar stays pinned; the table scrolls with the checklist. On a 1470 pt window put the
   checklist left and chart + table right, so a seven-step workout needs no scrolling.
   Add a preview scenario `preflight-workout` (Sweet spot 3×12, FTP 245 W, intensity 100 %).
6. **Chaindance is parked and leaves the build** (owner decision 2026-11-15). The app contains
   no Chaindance drawing code and no control for it; the code is kept in the repository so it
   can return.
   - Move to a new top-level `Parked/Chaindance/` (outside `App/`, `Sources/`, `Tests/`, so
     neither `Package.swift` nor `Tools/generate_project.py` picks it up):
     `App/Features/Ride/RideVisualRaster.swift`, `RideVisualRider.swift`,
     `RideVisualSprite.swift`, `PixelCanvas.swift` and the visual's views from
     `RideVisualStrip.swift` (`RideVisualStrip`, `RideVisualHero`, `HeroReadout`,
     `RideVisualMenu`, `RideVisualMenuView`, `RideVisualImage`, `RideVisualClock`,
     `TrackVisibility`), with their tests (`RideVisualRasterTests`, `RideVisualSpriteTests`,
     `ChaindanceFixtureTests`, the raster part of `RampFinishTests`).
     `contracts/fixtures/chaindance-fingerprints.json` stays untouched: the web tests read it.
   - Keep in the build what other code needs from those files: `RideOptionsMenu`, `ReadWidth`
     and the `RideVisualInput(model:engine:)` initializer (move them to
     `App/Features/Ride/RideExtras.swift`). `RideVisualState` in
     `Sources/FTPunkDomain/RideVisual.swift` stays, because the FTP cockpit's coaching line and
     the standing rule are computed from it; its tests stay. Move a domain file only if nothing
     built uses it any more (check `RideVisualMotion.swift`).
   - Remove the controls and branches: the pre-flight toggle (`pixelRideRow`, in workout and
     test rows), both Chaindance blocks in `App/Features/Settings/SettingsView.swift`, the
     "Cycle Chaindance view" command and the launch switch in `App/FTPunkApp.swift`,
     `RideVisualMenu` in `DashHeader.swift` and `FTPCockpitView.swift`, the strip and Large
     branches in `RideDashboard.swift` and `FTPCockpitView.swift` (the profile strip is always
     shown), `rideVisualPlacement` / `rideVisualEnabled` in `AppModel`, the `visual-*` preview
     scenarios and `captureStrips` in `App/Preview/`, the Chaindance XCUITest and the
     `pixel-ride-toggle` checks, and the tests that only cover placement.
   - Every ride screen must look exactly as it does today with Chaindance off, the FTP test
     included. Stored preferences are neither read nor deleted.
   - `App/DesignSystem/ChaindanceStyle.swift` is the dashboard's box style, not the visual. It
     stays; do not rename it in this plan.
   - README: replace the Chaindance bullet and the default-off sentences by one line (parked,
     sources in `Parked/Chaindance/`). Roadmap: "What FTPunk is" and "Where it stands" say
     parked; remove the parked item "Add a Chaindance-off preview scenario" (no longer
     applies). Regenerate the Xcode project.
7. **Highlight the current step in the workout profile.** `App/DesignSystem/WorkoutProfileChart.swift`
   draws finished bars at 40 % and everything else alike. Add a `currentStep: Int?` parameter
   (the dashboard passes `engine.currentStep?.index`, `App/Features/Ride/RideDashboard.swift:347`):
   finished bars stay at 40 %, the current step's bars are full strength with a 2 pt outline
   in the text colour, upcoming bars are drawn at 75 %. A step made of several bars (a ramp)
   is outlined as one shape. The progress marker, the heart-rate line and the step heart-rate
   averages are unchanged, and so are callers that pass no current step (detail sheet,
   pre-flight, summary). The state of a bar (finished, current, upcoming) is a pure function
   in `FTPunkDomain` with tests, including ramps and repeated steps.
8. **Step count in the time tile.** In the workout dashboard's time tile
   (`RideDashboard.swift`, `timeTile`), show "6/8" at the right end of the caption row
   ("Step left"), in the size and weight the Next tile uses for its duration: current step
   number and number of steps of the plan as ridden (repeats counted one by one, i.e.
   `engine.currentStep.index + 1` of `plan.steps.count`). Not shown for free rides, the FTP
   test, before the first step or after the last. While paused it follows the tile's paused
   colours. Accessibility: "Step 6 of 8". The text is a pure function with tests (nil cases
   included).
9. **Power matching in workouts and free ERG rides.** One `PowerMatcher`
   (`Sources/FTPunkDevices/PowerMatcher.swift`) serves every ride (`App/AppModel.swift:394`
   and `:494`). Findings from the 15 Nov ride:
   - work intervals were held well: 220 W targets averaged 220.5 / 220.4 / 221.6 W, the 147 W
     warm-up 147.6 W;
   - recoveries ran low: 122 W targets averaged 114.3 / 117.7 / 119.5 W (−6.3 / −3.5 / −2.0 %);
   - the fade guard held for 444 s (14 % of the ride) with a rider who was not fading, from
     the 26th second of the warm-up and after each drop to recovery (command stuck at 103 W
     for 45 s). Its trigger, the trainer reading 3 % under its command for 3 s, is about 4 W
     at these powers, less than the Suito's 10–12 W reading noise; while it holds, the
     estimate is frozen and the correction cannot grow;
   - the gain/offset estimate drifts inside a steady step (one power level cannot separate
     gain from offset; the true line was about gain 1.19–1.23, offset −33…−35 W), which biases
     the first command of the next step: the first work interval started near 242 W for
     10–15 s;
   - 88 command changes in the 10-minute steady warm-up;
   - nothing about the matcher is logged in a workout (`logPowerMatching` only logs ramps).

   Changes, all behind a tuning value so that **the FTP test keeps today's matcher**:
   - Give `PowerMatcher` a `Tuning` (constants only). `.ramp` holds today's values and is the
     default; `.training` holds the new ones. `AppModel` creates the matcher with `.training`
     for workouts and free ERG rides and with `.ramp` for the FTP test. With `.ramp` the
     matcher must be bit-for-bit today's: `PowerMatchingRampSimulationTests`,
     `PowerMatchingTests` and `PowerMatchingFixtureTests` pass unchanged and
     `contracts/fixtures/power-matching-replay.json` has no diff (the web port replays it).
   - `.training`, fade guard: judge the smoothed trainer reading (same 2 s smoothing as the
     estimator) instead of one sample; the shortfall must exceed the larger of 3 % and 8 W,
     for 5 s; after a target decrease wait 12 s before judging (4 s after an increase, as
     today); a target decrease ends a hold.
   - `.training`, estimator: once the target has been unchanged for 30 s, a measurement
     corrects only the offset; gain (and its variance) is learned in the first 30 s after a
     target change, when the level has moved.
   - `.training`, controller: the command moves only when the wanted value is 3 W or more
     away from it (1 W today). Step size, interval and feed-forward on a new target stay.
   - Logging for workouts and free ERG: one event line at each step change (gain, offset,
     trainer warmth, fade-guard seconds, measurement count; the ramp line's format) and one
     line when a hold starts and when it ends ("Fade guard held 45 s at 103 W"), at most one
     pair per 30 s. The text is built by a pure function with tests.
   - Tests (synthetic, closed loop, in the style of `PowerMatchingFixtureTests`; do not commit
     the owner's ride): a trainer with true gain 1.2, offset −34 W and ±11 W reading noise
     riding 10 min at 147 W, then 3 × (12 min at 220 W, 4 min at 122 W). With `.training`:
     total fade hold under 30 s; each recovery's average within ±2 % of target and each work
     interval's within ±1 %; the first 15 s of each work interval average within ±4 % of
     target; at most 25 command changes in the warm-up. A rider who really fades (cadence
     collapsing against the torque limit, as in `aFadingRiderNeverMakesTheLoadHarder`) is
     still held within 8 s and the load never rises during the hold.
   - The constants above are starting values. If the synthetic ride cannot meet the numbers
     with them, adjust constants only and report the final values; do not add another
     mechanism without asking. If the owner provides the ride's CSV export, also run
     `FTPUNK_REPLAY_CSV=<file> swift test --filter replay` and report the result.

## Still open (ask the owner if it matters while building)

- Should the FTP test get the `.training` fade guard as well? The same false holds can happen
  in the ramp's low-power warm-up, where they freeze the estimate. This plan leaves the test
  untouched.
- Remembering the last warm trainer model per trainer would remove the cold-start error of
  the first minutes. It contradicts the 2026-11-04 decision (no learned profile across
  rides), so it is not in this plan.

## Not in this plan

The web app (it keeps Chaindance and today's matcher), iPhone-specific layout work, any
change to the FTP test, renaming the `Chaindance*` dashboard styles.

## Done

`swift test` passes and both CI builds pass (commands in `AGENTS.md`); the Xcode project is
regenerated; `git diff` shows no change to `contracts/fixtures/`. Report the final matcher
constants and anything unverified. Move this file to `docs/archive/` and update the roadmap.
Then ask the owner before any visual review; for it, capture `app-home`, `app-progress`,
`preflight-workout`, `dash-workout` and one `dash-ftp-*` scenario at 1470×923. Hover states
cannot be captured by the walkthrough and need the owner's pointer or a permitted live check.
