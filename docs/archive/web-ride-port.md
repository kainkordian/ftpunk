# Web: port the 2026-11-11 native ride changes

The owner asked for this on 2026-11-11. The native app gained a new workout dashboard and several additions to the
ride overview that day. The web app (`ftpunk_web/`) has none of them yet. Bring it level, behaving the same way as
native. The native code is the reference. Read it before writing the web version:

| Commit | What | Native files |
|---|---|---|
| 89e1d08 | Chaindance-style workout dashboard, Skip step, heart-rate line on the profile | `App/Features/Ride/WorkoutCockpitView.swift`, `App/DesignSystem/ChaindanceStyle.swift`, `App/DesignSystem/WorkoutProfileChart.swift`, `Sources/FTPunkDomain/RampEngine.swift` (`skipStep`, `canSkipStep`, `skippedSeconds`), `Sources/FTPunkDomain/RideSummary.swift` (`WorkoutClock`) |
| 9964d04 | Trainer average power and NP, hover readings on the result charts, FIT hold of cadence and power | `Sources/FTPunkDomain/RideSummary.swift` (`trainerAveragePower`, `trainerNormalizedPower`, `RideMoment`, `TargetSeries.value`), `App/DesignSystem/RideChartHover.swift`, `App/DesignSystem/RideCharts.swift`, `App/DesignSystem/ResultPowerChart.swift`, `Sources/FTPunkStorage/FITEncoder.swift` (`merge`, `holdSeconds`) |
| 559424b | HRV: RMSSD figure and DFA α1 chart | `Sources/FTPunkDomain/HeartRateVariability.swift`, `RideAlphaChart` in `App/DesignSystem/RideCharts.swift` |

The Swift tests for each of these are the spec for the web tests:
- `Tests/FTPunkTests/WorkoutFeaturesTests.swift` (`skippingAStep…`)
- `Tests/FTPunkTests/RideSummaryTests.swift` (`trainerPower…`, `aMomentOfTheRecording…`)
- `Tests/FTPunkTests/FITExportTests.swift` (`fitHoldsAMissingCadence…`, `fitMergesNotifications…`)
- `Tests/FTPunkTests/HeartRateVariabilityTests.swift`

Port their cases, with the same numbers, into `ftpunk_web/tests/`.

The web app already records `trainerPower`, `rrIntervals` and `leftBalance` per sample (`src/protocol.mjs`), so
nothing new needs recording.

## Work, in this order

1. **FIT parity first (`src/fit.mjs`).** Native and web FIT files must be byte-identical for the same session JSON
   (`Tests/FTPunkTests/FITFixtureTests.swift`, fixtures in `contracts/fixtures/` and `ftpunk_web/tests/fixtures/`).
   - Port the hold from `FITEncoder.merge`: after merging per second, a record without cadence or power takes the
     last value if it is at most 3 s old. Same order, same rule for both fields.
   - Add a web test with the native test's numbers.
   - If the shared fixtures have no gap, they stay unchanged. Don't regenerate them unless a native test changes.
2. **Skip step (`src/domain.mjs` engine, `src/controller.mjs`).** Same rules as native:
   - Only in a workout, while riding or paused, never on the last step.
   - The skipped seconds move the training clock.
   - The event message comes from `WorkoutClock.skipMessage`, character for character ("Skipped ahead 15.0 s to step 2").
     A session synced or archived between the apps must read the same.
   - The target is re-sent through the normal tick path. Power matching restarts its settle (native `AppModel.skipStep`).
   - The summary's target line (`targetFunction` in `src/rules/ride-summary.mjs`) must honour skips, as native
     `WorkoutClock.trainingTime(at:)` does.
3. **Dashboard (`src/ui/ride.mjs`, `src/ui/ride.css`, `src/ui/components.mjs`).** Workout and free-ride cockpits only.
   The FTP test cockpit stays exactly as it is.
   - Follow `WorkoutCockpitView.swift` and the Chaindance palette in `ChaindanceStyle.swift`:
     - Square boxes with a 3 px border and uppercase captions.
     - STEP LEFT as the biggest number (ACTUAL in a free ride).
     - TARGET in lime, with its −/+ inside the box and the intensity % in its corner. Keep the existing ids and ↑/↓ keys.
     - ACTUAL with "TR <watts>" bottom-left while a meter is the source.
     - The profile with a red heart-rate line on its own bpm scale (line breaks at gaps over 5 s), the NEXT step text,
       and a Skip step button (keyboard: ⌘/Ctrl+→).
     - A row with ♥ BPM, RPM, and INTENSITY (Work kJ in a free ride).
     - The full figure grid always shown: Avg/NP/Max power, Avg/Max HR, Avg RPM, Work, Calories, Speed, Distance, Balance.
     - Then the live power chart.
   - The cockpit is dark regardless of the theme.
   - Remove the Chaindance rider scene and its placement menu from these two cockpits only, as native did. Keep
     `src/chaindance/` itself: the FTP cockpit and its tests use it.
   - Keep the per-tick update path that touches only changed text (see the comment at the top of `ride.mjs`). The 2026-11-04
     flicker bug came from rebuilding the header on each tick.
4. **Ride overview (`src/rules/ride-summary.mjs`, `src/ui/charts.mjs`, `src/ui/result.css`).**
   - **Trainer power:** average and NP from `trainerPower`, only while the power source is the external meter. Paused
     samples are excluded, same as native.
   - **Hover readings:** on the power, heart-rate, balance and α1 charts.
     - A pure `rideMoment(session, time)` in the rules returns the latest value within 2 s before `time` for power,
       trainer power, heart rate, cadence and balance, plus the target.
     - Pointer move or tap draws a vertical rule on every chart at that time. The chart under the pointer shows a card
       with clock time and the values that exist. Pointer leave clears it.
     - Hovering must not re-render the charts' paths. Update only an overlay.
   - **HRV:** port `HeartRateVariability` exactly (artifact filter, RMSSD, DFA α1 box sizes 4–16, 120 s windows every 30 s,
     ≤ 5 % rejected, no window across a gap over 3 s). Use the native test signals so both give the same numbers.
     - The summary shows "HRV (RMSSD)", plus "Beat artifacts" when the share is 1 % or more.
     - The α1 chart sits under heart rate, with dashed reference lines at 0.75 and 0.5 and the caption
       "0.75 ≈ aerobic threshold · 0.5 ≈ anaerobic".
5. **Release housekeeping.** Bump the cache name in `ftpunk_web/sw.js` by one (it is `ftpunk-web-v12`; check it first).
   Remove the "Web: port the 2026-11-11 native workout dashboard…" line from the roadmap's Parked list and add a
   "Where it stands" bullet.

## Rules

- Don't change ramp scoring, the ramp protocol, the 72 % factor or the FTP cockpit.
- Pure logic goes in `src/rules/` or `src/domain.mjs` with tests. UI files stay thin.
- Don't touch native code, `dist/`, or the running app. Don't open browsers or take screenshots: a visual check needs
  the owner's permission and is not part of this plan.
- Don't commit or push. A push to main deploys the web app to GitHub Pages.

## Done

- `cd ftpunk_web && CI=true python3 tools/test.py` passes, with the new tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` still passes. It includes the FIT fixture
  parity test.
- This plan moved to `docs/archive/` and the roadmap updated.
- The report lists what was not verified. The visual check is one item; any web/native difference left is another.
