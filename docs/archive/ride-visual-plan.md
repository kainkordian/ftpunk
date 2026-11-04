# Pixel ride visual and story removal

Status: approved direction, 2 November 2026. Follows [ux-rework-plan.md](ux-rework-plan.md).
Native iPhone/Mac first; the web app follows one phase behind.

## 1. Decisions

- **The Lowline story mode is removed.** Its 20-minute chapter was used up in one ride,
  and a good story would need ongoing writing, art and a web/Miyoo port. The playful layer
  moves into the ride visual instead.
- **Stelvio becomes the pixel ride visual for every ride type**: FTP test, workouts, free ERG
  and resistance. It stays pretty, takes on a cyberpunk aesthetic, and **the avatar shows the
  rider's current intensity**.
- **Side view instead of the third-person rear view.** A side-scroller shows posture,
  pedalling and effort clearly, fits a short full-width strip, and works the same for climbing
  (FTP test) and flat riding (workouts).
- **Climbing only in the FTP test.** Workouts and free rides ride a flat neon boulevard.
- **Toggleable everywhere**: in pre-flight for tests and workouts, live in the cockpit's ⋯
  menu, and in Settings → Ride display.

## 2. Look and feel

A rainy night city seen from an elevated road, as low-resolution pixel art scaled with
nearest-neighbour sampling, like the current `StelvioRaster`.

- **Palette**: deep indigo/navy night, neon magenta (the app icon's helmet), cyan and the app's
  lime accent, with the shared zone colours (§3) for everything intensity-related. Wet road
  with soft reflections of the neon.
- **Layers, back to front**:
  1. Far skyline silhouettes with a few blinking windows.
  2. Mid towers with neon signs (simple glyphs and short words like `24H`, `WATT`, `FTP`;
     no fake foreign-language text).
  3. The road's railing and lamp posts.
  4. Wet road surface with puddle reflections.
  5. Diagonal rain.

  Layers scroll at different speeds (parallax).
- **Avatar**: the app-icon cyclist in profile, facing right, about a third in from the left:
  magenta helmet, lime jacket, dark bike with cyan rims. The world scrolls; the rider stays put.
- **Always night**, in both light and dark mode; only the frame around the strip follows the
  theme. Neon needs the dark.
- **No flashing** above 3 Hz, no full-screen effects, nothing that covers metrics or controls.

## 3. Intensity on the avatar

Intensity is **measured power** smoothed over 3 s, as % of the FTP used for the ride.
It uses the same zones and colours as the workout profile charts (one shared definition in
the domain/design system):

| Zone | % FTP | Avatar |
| --- | --- | --- |
| Recovery | < 56 | Upright, hands on the tops, short dim trail |
| Endurance | 56–75 | Relaxed on the hoods |
| Tempo | 76–87 | Lower torso, elbows bent, trail in zone colour |
| Sweet spot | 88–94 | As tempo, longer trail |
| Threshold | 95–105 | Down in the drops, head low, sweat drops, speed lines |
| VO2max | > 105 | Drops, head low, sweat, speed lines, sparks from the rear wheel |

- **Zone colour** lights the bike's underglow, the light trail and a stripe on the jacket.
- **Pedalling** follows measured cadence: a 4-frame pedal cycle at the rider's real rpm.
  Stale or zero cadence shows a coasting pose.
- **World speed** follows measured power (clamped), so harder riding visibly moves faster;
  rain slants more at speed.
- The rider **always stays seated**, matching the FTP test's "stay seated" coaching.
- **No FTP**: neutral cyan, the endurance pose, and cadence/speed still animate.
- **Paused** (workouts, free ride): the rider stops with a foot down; a `PAUSED` sign appears.

## 4. Worlds per ride type

**FTP test – "The Spire"**
- **Warm-up**: the flat boulevard towards a megatower.
- **Ramp**: the road becomes a skyway spiralling up the tower, and the skyline sinks as the
  rider rises.
  - Each ramp step passes a level sign, `LVL n`, where n is the step number, so the visual
    reinforces the step count.
  - The climb is endless: it never predicts where the ramp will end (keep the existing
    "doesn't predict the finish" test).
- **Finish**: a rooftop with the city panorama and a static neon sign showing the level
  reached and the best minute, e.g. `LVL 23 · 290 W`. No fireworks or flashing.
- **Cool-down**: a calm glide down the skyway.

**Workouts – "Neon Boulevard"**
- Flat elevated road through districts. At each step boundary the rider passes a gantry, and
  the district changes:
  - recovery steps: calm teal residential blocks;
  - work steps: a bright market district in the step's zone colour.
- About 10 s before a boundary, a billboard ahead previews the next step (`NEXT 5:00 · 225 W`).
- Ramp steps (warm-up ramps) brighten gradually.

**Free ERG and resistance**
- An endless boulevard. Each ERG target change passes a small gate sign with the new target
  (`150 W`). Resistance shows the level instead.

**Debug playback**: animation speed follows the mock playback speed (as Stelvio does today).

## 5. Layout, toggle, accessibility, performance

- **One strip component** (`RideVisualStrip`), full width, fixed short aspect (about 16:5),
  rounded corners. It sits in the same place in every phase and every cockpit, so nothing
  jumps. It replaces the current Stelvio scene, thumbnail and strip.
- **Toggle**:
  - One preference, `rideVisualEnabled`, migrated from `showStelvioASCII` (absent → on; an
    explicitly stored `false` → off).
  - Exposed in pre-flight ("Pixel ride", for tests and workouts), the cockpit ⋯ menu (live),
    and Settings → Ride display.
  - When off, the cockpit reflows to metrics only.
- **Accessibility**:
  - The strip is decorative, with a summary label ("Pixel ride: threshold effort, level 14")
    and no announcements.
  - Reduce Motion: no scrolling, parallax, rain or pedal animation. Pose, colour and signs
    still update on zone/step changes.
  - Increase Contrast adds a dark outline around the rider.
- **Performance**: animate at about 12 fps with `TimelineView`, and stop when off screen, in
  the background, or under Reduce Motion. Keep the raster small (about 192 × 60) and pixels
  crisp.

## 6. Story removal

Before any deletion, save a snapshot of the working tree. The story code has never been
committed, so this backup is the only way back.

**Remove from the native app**:
- the Story tab/destination, the Home story card and the Settings → Story group;
- the pre-flight story row, result/detail story receipts and the calibration log line;
- the in-ride story line;
- `CitySceneView`, `CityBeat`, `RideRewards`, `CalibrationLog`, `StorySummary`,
  `StoryDialogue` and their rules;
- the story preview scenarios and UI tests, and the `cyclepunkEnabled` preference.

**Keep for compatibility**:
- `CycleProgress` on riders, and the session fields `adventureEnabled`,
  `adventureStartMilliseconds` and `eligibleMilliseconds`, still decoded, validated and
  preserved unchanged through storage and portable archive import/export (v1–v3). Backups
  from the web app, which still has the story until its port, must round-trip without losing
  progress.
- New native sessions don't enable or accrue story progress.

Replace the story tests with compatibility tests (archives with progress import, export and
re-import unchanged).

**Docs**: README, the evolution plan (Cyclepunk removed from native; web pending; Miyoo no
longer needs story screens) and `contracts/README.md` (story fields are legacy and preserved).

## 7. Verification

- **Unit tests**:
  - a pure `RideVisualState`, derived from mode, phase, step, smoothed power, FTP, cadence and
    pause: zone, pose, pedal period, world speed, level number and sign text;
  - shared zone boundaries with the profile charts;
  - toggle migration;
  - archive compatibility after the story removal.
- **Raster smoke tests**: images render for each mode/zone; spot-check that the helmet and
  zone colours are present.
- **Preview scenarios**: `visual-ramp-threshold`, `visual-workout-vo2`, `visual-recovery`,
  `visual-summit`, `visual-paused`, `visual-off`. Existing ride scenarios show the visual by
  default.
- **Visual review** (screenshot matrix, UI tests) only with the user's permission for that
  review.

## 8. Implementation status

Implemented 2–3 November 2026 for the native iPhone and Mac apps. The web app is untouched and keeps its story.

**Pixel ride**
- `Sources/FTPunkDomain/RideVisual.swift`: the pure `RideVisualState` (mode, phase, step, smoothed power, FTP, cadence,
  pause, playback speed → zone, posture, pedal period, world speed, rain slant, district and glow, level and sign text,
  next-boundary preview, accessibility summary), `RideVisualSmoothing` (3 s mean, stale after 2 s) and
  `RideVisualPreference` (`rideVisualEnabled`, migrated from `showStelvioASCII`). Zones come from `IntensityZone`, the
  definition the profile charts use; colours come from `ZonePalette` (its dark-mode variants, since the strip is always night).
- `RideVisualMotion.swift`: the bookkeeping between frames (scroll distance, crank turns, announced signs and districts).
  Scenery repeats exactly every 1536 road pixels and 3 s, so nothing counts down to a finish.
- `App/Features/Ride/`: `PixelCanvas.swift` (`Ink`, `Pixels`, a 3 × 5 font; extended from the old Stelvio helpers),
  `RideVisualRaster.swift` (192 × 60 layers: sky and haze, far skyline, Spire, mid towers with neon signs, shopfronts,
  railing and lamps, wet road, passing signs, rain), `RideVisualRider.swift` (the icon cyclist built from joints, tilted with
  the road, four crank frames, four postures, foot-down and coasting, zone underglow, trail, sweat, speed lines, sparks,
  head and tail lights, the Increase Contrast outline) and `RideVisualStrip.swift` (`TimelineView` at about 12 fps, paused
  off screen, in the background, under Reduce Motion, while the debug stream is paused and when the ride has ended).
  `StelvioRaster` and `StelvioView` are deleted.
- The strip sits directly under the target and actual numbers in both cockpits, in every phase. The toggle is in the
  pre-flight of tests and workouts, the cockpit ⋯ menu and Settings → Ride display. With the pixel ride on, the FTP cockpit
  drops its coaching line (`CockpitLayout.make(…, rideVisual:)`), which fixes the line sitting behind the pinned bar in
  warm-up; with it off the line is shown as before.
- Preview scenarios `visual-ramp-threshold`, `visual-workout-vo2`, `visual-recovery`, `visual-summit`, `visual-paused` and
  `visual-off` are in `PreviewScenario` (so in `--scenario-matrix` and the Mac walkthrough) and in the
  `Tools/run_simulator.sh --matrix` list. The walkthrough captures the strip on its own at eight efforts. A preview can now
  be started with `--mock-speed <n>`.

**Story removal**
- Removed: the Story tab and view, `CitySceneView`, the Home card, the Settings group and topic, the pre-flight row, result
  and detail receipts, the in-ride line, `CityBeat`, `RideRewards`, `CalibrationLog`, `StorySummary`, `StoryDialogue`, the
  three story scenarios, the story UI tests, `cyclepunkEnabled` (its stored key is cleared on launch), and the accrual in
  `RideEngine` (the `adventure:` parameters and the eligible-time counter; scoring, protocols and the automatic finish are
  untouched).
- Kept for compatibility: `CycleProgress` on riders and the session fields `adventureEnabled`,
  `adventureStartMilliseconds` and `eligibleMilliseconds`, decoded, validated and preserved unchanged through storage and
  archives v1–v3. `LocalStore` still credits a legacy recording's ledger idempotently. New native sessions leave the three
  session fields empty. `StoryCompatibilityTests` import the shared web v2 and v3 fixtures, export, re-import and compare.

**UI test fixes** (compiled, not run): `testFTPTestFromHomeToDebugResult` launches with `--mock-speed 4` (at 12× the ramp
reached exhaustion, 40 steps of 12 s, in about 40 s of wall time, while the test was in the debug menu) and waits for
Hold to finish right after the skip; `testProgressFiltersByRiderAndDeletesBySwipe` collects the row identifiers while
scrolling instead of counting a lazily loaded list. New UI tests cover the pixel ride (default on, menu toggle, workout
pause label, off scenario, Settings and pre-flight switches) and the absence of the story.

**Verification**
- `swift test`: 205 passing (180 before). New tests: `RideVisualTests` (state, zones shared with the chart bars at every
  wattage, postures, pedal period, speed, FTP and workout worlds, previews, smoothing, toggle migration, motion),
  `RideVisualRasterTests` (every mode and zone renders, helmet and zone colour present, poses differ, four crank frames,
  Reduce Motion is steady, Increase Contrast outline, exact repetition after one loop, no trap at any offset),
  `RampFinishTests` (the ramp-boundary tests ported from Stelvio, and that reading a ride never changes it) and
  `StoryCompatibilityTests`.
- Builds succeed: iOS Simulator (`generic/platform=iOS Simulator`), macOS (`FTPunkMac`), `build-for-testing` for the iPhone 15
  Pro simulator, and `sh Tools/build_mac.sh`.

**Not verified**
- No visual review was made: the artwork was designed from pixel grids and checked as text dumps and unit tests, never as an
  image, so composition, palette balance and how it reads at size are unreviewed. The screenshot matrix, the walkthrough
  and all XCUITests are written and compile but have not been run.
- Frame cost was timed only in a debug macOS build (about 14 ms a frame); an iPhone has not been measured.
- Layout heights were estimated from the code. On an iPhone 15 Pro the workout cockpit's intensity buttons now sit below the
  fold at the first scroll position; the FTP cockpit's readings and tiles fit.
- Physical trainer, iPhone and Miyoo checks remain deferred.
