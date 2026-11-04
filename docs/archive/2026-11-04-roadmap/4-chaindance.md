# 4 — "Chaindance": rename, a real hero view, ride polish

## A. Rename "Pixel ride" → **Chaindance**

The owner asked for a clever name in the spirit of cyberpunk and cycling. **Chaindance**:

- a riff on the cyberpunk idea of living through someone else's recorded senses: here
  you watch your own ride played out by a neon avatar;
- *chain*, the drivetrain;
- *en danseuse*, "dancing on the pedals", the cycling term for riding out of the saddle,
  which is exactly what the avatar now does at sprint power.

It's an original word. Don't use names, places or terms taken directly from any
existing game.

- `Sources/FTPunkDomain/RideVisual.swift`: `RideVisualBranding.name = "Chaindance"`.
  Every user-facing string already goes through this constant. Check with
  `grep -rni "pixel ride" App Sources Tests README.md docs` and fix any leftovers.
- Menu labels: "Chaindance: Off / Strip / Large". The macOS command becomes "Cycle
  Chaindance view" (⌘⇧R, unchanged). The Settings toggle is "Show Chaindance during
  rides". Footer: "A neon night-city ride that follows your power. It never controls
  the trainer."
- Keep the stored preference key and the accessibility identifiers (`pixel-ride-toggle`,
  `ride-visual`) unchanged. Update tests that assert visible text.

## B. Make "Large" (hero) actually large and never cover the rider

Visual check findings: hero is the same size as the strip, because the raster is fixed
at 192×60 (`RideVisualRaster.width/height`) and drawn `.fit`. The readout bar sits over
the rider. In a wide Mac window the left column has empty space under the scene.

1. **Taller raster for hero.** Add a height parameter to the raster renderer:
   `RideVisualRaster.stripHeight = 60` and `heroHeight = 96`. In hero, the extra 36 rows
   are **sky at the top**: stars, a moon and a few distant tower tips. The road, rider and
   skyline keep their exact row offsets relative to the bottom edge. The existing
   strip raster must stay pixel-identical: `RideVisualRasterTests` snapshots must not
   change. Add a hero snapshot test.
2. **Readout in the sky.** Move the `RideVisualHero` overlay to `alignment: .top` and
   limit its height to the sky band: view height × 36/96, read with `GeometryReader`.
   Use no material behind it, or a very light dark-gradient scrim fading out downwards.
   Keep the white/accent digits, and check that contrast against the sky colour
   `Ink(10, 10, 32)` is ≥ 4.5:1. Write a pure test in Domain:
   `HeroLayout.readoutFraction == 36.0/96`, and the rider's topmost pixel row in the
   hero raster is > 36, so the two can't overlap.
3. **Use the space.**
   - iPhone / narrow: the scene takes the full content width, with no 760 pt cap in
     hero mode.
   - Wide Mac/iPad (`CockpitLayout`, width ≥ 900): left column = scene, then directly
     below it the "Up next"/step list (workouts) or ramp progress (FTP test). Right column =
     the metric tiles. The goal is no tall empty area in either column. Put the decision
     in `CockpitLayout.make(...)` and test it.
4. Keep: the accessibility-size fallback to strip, Reduce Motion, 12 fps, and no
   animation off screen.

## C. Coaching and labels

- **"Stay seated" only in the FTP test warm-up and ramp.** In
  `App/Features/Ride/WorkoutCockpitView.swift:206` (workouts, free ERG, resistance),
  replace it with "Keep a steady, comfortable cadence." When the ride visual state is
  standing, show "Sprint — out of the saddle is fine." instead. Take that from the same
  pure rule (`RideVisualState`), so the avatar and the text agree.
  `FTPCockpitView.swift:88` and the FTP-test preflight text stay as they are.
- **Devices row, no double "Optional".** `App/DesignSystem/DeviceStatusRow.swift`: the
  badge says Required/Optional, so the subtitles become "For power matching, or as the
  power source" (power meter) and "Heart rate on screen and in the file" (HRM). Leave the
  trainer subtitle as it is.
- **API key field alignment (macOS).** In `SettingsView`, the API key `SecureField`
  text is right-aligned in the Form. Add `.multilineTextAlignment(.leading)`.

## Tests

The raster tests above, `CockpitLayout` hero/wide cases, coaching text rule (workout +
standing → sprint line; FTP-test ramp at 700 W → "Stay seated"), and the renamed strings.
