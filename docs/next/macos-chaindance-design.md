# Mac app in the Chaindance look

Owner-requested plan (2026-11-11). Mockup: the private "FTPunk Mac · Chaindance look" design
canvas (five 1280×800 boards: Home, FTP test cockpit, Workout cockpit, Ride summary, Log).
Visual only: no change to ride logic, trainer control, ramp protocol, scoring or the 72 % estimate.

## Goal

Carry the workout dashboard's Chaindance style (already in `App/DesignSystem/ChaindanceStyle.swift`)
to the whole Mac app: deep blue-black surfaces, square boxes with a 3 pt outline, small
uppercase captions top-left, heavy tabular numbers, neon accents with a soft glow, keyboard
hints in a footer. iOS keeps its current look until the Mac version has been used.

## Decisions for the owner (before step 1)

1. **Dark only or a light variant?** The style only works dark. Recommendation: on Mac add a
   third appearance option, "Chaindance", and make it the default; System/Light/Dark keep the
   current look. A light Chaindance is not planned.
2. **Font.** The mockup uses Tektur (SIL Open Font License 1.1, free to bundle). Alternative: keep
   SF Rounded (what the dashboard uses now), with no licence file and no bundle size. Recommendation:
   Tektur for captions and numbers, SF for body text and settings forms.
3. **Glitch wordmark and synthwave grid on Home.** Decorative only; drop them if they feel too much.

## Colour roles (unchanged palette from `Chaindance`)

| Role | Colour | Used for |
|---|---|---|
| background / panel / panelRaised | #07051a / #0f0b27 / #181238 | window, boxes, hover cards |
| line | #2c2463 | box outlines, dividers (decorative, never the only signal) |
| dim / text | #9a94d0 / #ecf0fa | captions / values (both ≥ 4.5:1 on panel) |
| lime | #c5f74d | FTP, target, primary action, selected nav item |
| cyan | #00d3e0 | intensity, workouts, best 60 s |
| magenta / pink | #ff009a / #ff6fb8 | heart rate, Intervals.icu, destructive or hold actions |
| amber | #fcb852 | warnings (retest due, weak signal) |
| purple | #b48cff | DFA α1 only |

Status always comes with text or an icon, never colour alone.

## Steps

1. **Theme plumbing.** Extend `Chaindance` with the tokens above (add `purple`), a
   `ChaindanceTheme` environment flag set by the new appearance option, and a `chaindanceFont`
   helper (Tektur if bundled, SF Rounded otherwise). If Tektur is chosen: add the TTFs and
   `OFL.txt` under `App/Resources/Fonts/`, `ATSApplicationFontsPath` in `MacInfo.plist`,
   and regenerate the project. Tests: none needed beyond builds; keep `swift test` green.
2. **Buttons and controls.** Chaindance variants of `FTPunkPrimaryButtonStyle` (lime fill, dark
   text, square), secondary (3 pt outline in the accent colour), tertiary (text only), the row
   button and toggle style, `FilterChip` as a segmented outline group, `HoldToConfirmButton`
   in magenta. Chosen by the theme flag, so the current styles stay for the other options.
3. **Shell and sidebar** (`Features/Shell`). Sidebar on `panel` with the wordmark, nav items
   with ▶ and a lime outline on the selected one, the devices box with pips at the bottom
   (reuse `DeviceStatusRow` data). Rider switcher in the content header. ⌘1–4 for the
   sections stays as it is.
4. **Home** (`Features/Home`). FTP box (big FTP, W/kg, retest note from the existing state, Start
   ramp test), Today panel for the Intervals.icu workout, rows for library, free ride and log.
   Sheets (devices, rider, workout detail) get the box/caption treatment.
5. **FTP test cockpit** (`FTPCockpitView`). Same layout and data as now: TARGET and ACTUAL boxes
   (with TR when a meter is the source), the step countdown as segments, ♥ / RPM / best 60 s,
   footer key hints. Only the drawing changes: no new readings, nothing about the protocol.
   Check that `StepCountdownRing`'s replacement still reads at a glance from the bike.
6. **Result and ride summary** (`Features/Result`, `RideCharts`). TSS box, figure grid
   (avg/NP, trainer avg/NP, HR, cadence, work, balance, RMSSD, artifacts), power chart with
   the existing hover card restyled, HR and α1 charts side by side. Ramp test results keep
   their current content first (FTP result, adopt button).
7. **Log / Progress** (`Features/Progress`). FTP trend as a stepped line with square markers,
   activity table with a type tag (FTP / WO / FR), filter group, upload state arrow.
   `ActivityDetailView` reuses step 6.
8. **Settings and preflight.** Grouped boxes with captions; forms keep native controls
   inside so they stay accessible.
9. **Wrap-up.** Move this file to `docs/archive/`, update the roadmap's "Where it stands",
   rebuild `dist/FTPunk.app` (only while it isn't running). Ask the owner before a visual review.

## Accessibility and checks

- Dynamic Type: keep `@ScaledMetric` on numbers; captions use a text style, not a fixed size.
- Increase Contrast: the outline goes from `line` to `dim`; glows turn off with Reduce Transparency.
- VoiceOver labels unchanged (the restyle must not drop any).
- Done: `swift test` passes and both CI builds (iOS simulator and Mac) pass.

## Not in this plan

iOS restyle, the rider scene, new readings or features, web app changes.
