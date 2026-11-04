# 05 — Pixel ride: rename, in-ride access, standing sprint

*Implemented. The name is decided (Chaindance), and hero fixes are in [next/4-chaindance.md](../../next/4-chaindance.md).*

Three changes to the decorative night-city strip ("Pixel ride").

## A. Rename

The owner wants a new name. **The owner chooses it**; don't pick one yourself. Candidates
for the owner: "Neon Ride", "Night Run", "City Ride", "Punk Ride". Until the owner
decides, put the display name in one constant and use it everywhere:

```swift
// App/Features/Ride/RideVisualStrip.swift (or AppInfo)
enum RideVisualBranding { static let name = "<OWNER CHOICE>" }
```

Replace every user-facing "Pixel ride" / "pixel ride" string: Settings toggle and footer,
both cockpit menus, accessibility summaries in `Sources/FTPunkDomain/RideVisual.swift`
("Pixel ride: …"), `CockpitLayout` comment, README/docs. Find them all with
`grep -rni "pixel ride" App Sources Tests README.md docs`. Domain strings can't import
the App target, so pass the name in or keep a matching constant in `FTPunkDomain`.
**Keep** the stored preference key (`RideVisualPreference`) and the accessibility
identifiers (`pixel-ride-toggle`, `ride-visual`) so saved settings and UI tests keep
working. Update any tests that assert the visible text.

## B. Easy to reach and easy to see during a ride

Today it can only be switched on in Settings → Ride display, or through the "…" menu in the
cockpit header. It's capped at 480 pt wide and sits between metric tiles. On a Mac
window or iPad it's tiny.

1. **Visible toggle in the cockpit**: an icon button in the header of both
   `FTPCockpitView` and `WorkoutCockpitView`, next to the "…" menu (SF Symbol
   `sparkles.tv` or similar, 44×44, label "Show <name>"/"Hide <name>"). Remove the toggle
   from the "…" menu so there's one control. On macOS add a menu command + shortcut
   (⌘⇧P or similar) in `FTPunkApp.swift` commands.
2. **Pre-flight toggle**: a row in `PreflightView` ("Show <name> during the ride") so the
   rider sets it before clipping in.
3. **Size modes**: replace the Bool with an enum persisted through `RideVisualPreference`
   (migrate: `true` → `.strip`, `false` → `.off`):
   - `.off`
   - `.strip`: current placement, but drop the 480 pt cap; use the full content width
     (max 760, like the rest of the cockpit).
   - `.hero`: the scene fills the top of the cockpit. Target, power and the step/countdown
     sit in a translucent bar over the bottom edge of the scene (big monospaced digits,
     `.ultraThinMaterial` background, contrast-checked). The tiles below remain for
     the supporting metrics. On macOS in a wide window (`horizontalSizeClass == .regular`
     and width ≥ 900), put the scene left and the metrics in a right column.
   The header button cycles off → strip → hero, or opens a small menu with the three
   options. Pick whichever keeps the hit target simple, and say which you chose.
4. **Accessibility text sizes**: in `.hero`, when `dynamicTypeSize.isAccessibilitySize`,
   fall back to `.strip` placement below the hero tiles so the numbers stay first.
5. Keep the rules that already exist: no animation with Reduce Motion, off-screen or in
   the background; 12 fps; `accessibilityLabel` summary.
6. Put the layout decision in `CockpitLayout.make(...)` (pure, `PresentationRules.swift`)
   with a `rideVisualMode` input, and test it.

## C. Rider stands up at sprint power

### Rule (pure, `Sources/FTPunkDomain/RideVisual.swift`)

- Add `RidePosture.standing` (largest raw value) and `RideVisualInput.weightKG: Double?`
  (from `configuration.weightKG` in `RideVisualInput(model:engine:)`).
- Add `RideVisualInput.sprintPower: Double?`: power averaged over the last **1 s**
  (new helper next to `RideVisualSmoothing.power`, which uses 3 s and lags too much for
  a 5–10 s sprint).
- Standing threshold: **7 W/kg** (`RideVisualState.standingWattsPerKG = 7.0`). Seven
  instead of eight because 8 W/kg is out of reach for many amateurs' sprints, and 7
  is still well above any steady-state effort. Without a weight, use 1.6 × FTP
  (above the end of a ramp test, which is roughly FTP ÷ 0.72 ≈ 1.39 × FTP). With neither
  weight nor FTP: never stand.
- Hysteresis, without per-frame memory (keep `make` pure): stand if `sprintPower ≥
  threshold`, **or** if 3 s smoothed power ≥ 0.85 × threshold and some 1 s window in the
  last 3 s was ≥ threshold. This stops the rider bobbing up and down around the threshold.
- **FTP test:** the protocol and coaching say "Stay seated", so in `.ftpTest` mode during
  `.warmup` and `.ramp` the rider never stands. Standing is allowed in workouts, free
  ERG, resistance mode and FTP-test cooldown. (If the owner wants it in the ramp too, it's
  one condition.)
- Not while `motion != .pedalling`.
- `posture(for:)` keeps the zone mapping; standing overrides it. Standing also shows
  sparks/speed lines like VO2max.
- Update the doc comments that say "The rider always stays seated", in `RideVisual.swift`
  and in `CockpitLayout`.

### Sprite (`App/Features/Ride/RideVisualRider.swift`)

Add a `.standing` case to the posture switch: hip raised and forward over the bottom
bracket (about `hip = (9, -13)` instead of `(5, -9)`), torso more upright and forward
over the bars, hands on the hoods. The leg code already solves knees with IK from the
hip. Check that `knee(to:)` still finds a solution with the raised hip (upper + lower =
17 px), and shorten the hip height if it doesn't. Optionally rock the bike ±1 px per
pedal frame. The existing raster tests (`RideVisualRasterTests`) show how to snapshot a
posture; add one for `.standing`.

### Tests (`RideVisualTests`)

- 75 kg rider at 560 W, 1 s average → standing in workout mode; 500 W → seated.
- Hysteresis: 540 W smoothed after a 560 W second → still standing; 400 W → seated.
- No weight, FTP 250: 410 W → standing; 380 W → seated.
- FTP test `.ramp` at 700 W → seated. `.cooldown` sprint → standing.
- Coasting at high (stale) power → not standing.
- Accessibility summary mentions "sprinting out of the saddle" when standing.
