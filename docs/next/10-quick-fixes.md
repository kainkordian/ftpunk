# 10 · Quick fixes from the Mac walkthrough

Owner-requested plan (2026-11-12), from a click-through of `dist/FTPunk.app` (build of 11 Nov).
Four small fixes that do not depend on the redesign in plans 11 and 12. Run this first.
No change to ride logic, trainer control, the ramp protocol, scoring or the 72 % estimate.

## Tasks

1. **Workout cards cannot be activated through accessibility.** A mouse click opens the detail
   sheet; an accessibility press (VoiceOver, Voice Control, Full Keyboard Access) does nothing.
   `App/DesignSystem/WorkoutCard.swift` puts `.accessibilityElement(children: .ignore)` on the
   `Button`, which replaces the button's element and drops its press action. Remove that
   modifier and keep label, value and hint on the button itself (or keep the modifier and add
   `.accessibilityAction { action() }`). Check the same pattern in `TodayCard`
   (`Features/Home/TodaySection.swift`) and every other `.accessibilityElement(children: .ignore)`
   on a tappable view (the cockpit boxes only read values, they are fine). Add one XCUITest that
   opens a library card by its accessibility element.
2. **Chaindance is off by default.** `RideVisualPreference.resolve(stored:legacy:)` in
   `Sources/FTPunkDomain/RideVisual.swift` returns `stored ?? legacy ?? true`; make the last
   fallback `false`, so `resolvePlacement` yields `.off` when nothing is stored. A stored choice
   (on, strip or hero) is kept. Update the tests that expect "absent means on", the Settings
   footer text and the README sentence ("It is on by default"). No other Chaindance work.
3. **Import only real cycling workouts from Intervals.icu** (owner decision 2026-11-13).
   `IntervalsClient.decodeWorkouts` returns `skipped: [String]` and Home prints every line
   (about 20 for the owner: commutes, strength, mobility). New rule, as a pure function in
   `FTPunkDomain` with tests: an event is imported only if its sport is cycling (Ride or
   VirtualRide) **and** it has steps whose power targets are given in % of FTP (ramps
   included). Everything else (other sports, rides without steps, rides with only watts,
   heart-rate or pace targets) is dropped silently: no message, no "Skipped" list. A cycling
   % FTP workout that fails to decode is the only thing reported, as one line with the name.
   Home shows "7 cycling workouts with % FTP targets synced". Both places that print
   `model.catalog.syncMessage` use it. Workouts cached earlier that break the rule are removed
   at the next download. File import (JSON, ZWO) and the builder are not affected.
4. **Mac menu bar.** `App/FTPunkApp.swift` only adds "Cycle Chaindance view". Add:
   - app menu: **Settings…** ⌘, (sets `model.destination = .settings`);
   - **Go**: Home ⌘1, Progress ⌘2, Settings ⌘3;
   - **Ride** (enabled while a ride runs; each item calls what the cockpit button calls):
     Pause/Resume (Space, ⌘⇧P), Skip step ⌘→, Raise/Lower target ↑/↓, Finish ramp ⌘⇧F,
     Stop & save ⌘., More readings, Minimise ride. Keep the existing in-view shortcuts working;
   - remove **File › New Window** (`CommandGroup(replacing: .newItem) {}`) and switch window
     tabbing off (`NSWindow.allowsAutomaticWindowTabbing = false`), so "Show Tab Bar" goes away.

## Done

`swift test` passes, both CI builds pass (commands in `AGENTS.md`). Move this file to
`docs/archive/` and update the roadmap. Ask the owner before any visual review.
