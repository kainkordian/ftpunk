# 5 — Preview scenarios that also work in the iOS Simulator

During the last visual check, the new screens were captured only by the **macOS**
preview walkthrough, at an iPhone-sized window. That's macOS SwiftUI. Forms, toggles,
pickers, fonts, navigation, sheets, safe areas and text-size behaviour all differ from
real iOS. `Tools/run_simulator.sh --matrix` already captures every scenario in an iPhone
15 Pro simulator, light/dark × default/accessibility size, via `simctl`. Make the new
scenarios work there.

## Tasks

1. `workout-detail`: today the sheet is rendered off-screen by the Mac walkthrough only
   (`App/Preview/PreviewWalkthrough.swift`, `captureView`). Add
   `AppModel.previewWorkoutDetail: WorkoutRef?`. Set it **after** `resetPreview` in
   `PreviewScenarios` (the earlier attempt raced the reset). Present the real
   `WorkoutDetailSheet` from the view that normally presents it, when the value is set,
   then clear it. Keep the Mac off-screen capture as well.
2. `settings-devices` / `settings-intervals`: check that `previewSettingsAnchor`
   ordering works in the iOS `Form`. On iOS, `ScrollViewReader.scrollTo` may work. If it
   does, use it on iOS and keep the reordering for macOS only.
3. Add `settings-devices settings-intervals workout-detail visual-hero visual-sprint`
   to the default scenario list in `Tools/run_simulator.sh`.
4. Add a scenario `settings-intervals-connected` with a **fake** connection object and
   seeded sync state: linked rider, last synced, "FTP 230 W · 71 kg from Intervals.icu".
   This shows the sync UI without network or Keychain access. No real credentials in
   preview code.
5. `ShellAndScenarioTests.scenarioNamesMatchThePlan`: add the new names.

**Don't run the simulator or capture screenshots.** That's a visual review and needs the
owner's permission (`AGENTS.md`). Building for the simulator is fine.
