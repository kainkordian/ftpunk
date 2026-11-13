# 11 · One ride dashboard, readable from 2 m

Owner-requested plan (2026-11-12, revised 2026-11-13 after the owner's review of the mockups).
**Designs:** `design/app-redesign/1-workout.html`, `2-ftp-test-ramp.html`, `2b-ftp-test-warm-up.html`,
`3-free-ride.html` and
`3b-free-ride-more-metrics.html` (static HTML, 1470×920; read their inline sizes and colours).
Display and controls only: no change to trainer control, the ramp protocol, scoring, MAX 60 S
or the 72 % estimate. No work on Chaindance art. Run plan 10 first.

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

## Why

The owner rides with the app in full screen on a 13" MacBook Air M2 (1470×956 pt, about
0.195 mm per point) roughly 2 m from his eyes. At 2 m one arc minute is 0.58 mm.

| Reading today | Font | Digit height | At 2 m |
|---|---|---|---|
| Workout step time | 128 pt | ≈ 18 mm | fine |
| Workout heart rate, cadence | 60 pt | ≈ 8 mm | marginal |
| FTP test target / actual (`ftpNumber(.hero)`) | 72 pt | ≈ 10 mm | marginal |
| FTP test heart rate, cadence, MAX 60 S (`.metric`) | 38 pt | ≈ 5 mm | too small |
| All captions | 13 pt | ≈ 1.8 mm | below what the eye resolves (≈ 3 mm) |

Also: both cockpits are `ScrollView`s with fixed sizes and already scroll at 900×820; content
is capped at 1100 pt, so full screen adds margins instead of size; the FTP cockpit and the
workout cockpit look like two apps; power is the latest sample, not an average; a pause shows
two near-identical hints; "Workout time" jumps on Skip while the saved ride shows elapsed time.

## Requirements

- Full screen on the 13" Air (1470×923 usable): power and time digits ≥ 30 mm tall; heart rate,
  cadence and the third reading ≥ 20 mm; the target ≥ 9 mm; captions ≥ 4 mm.
- No scrolling on Mac at any window size from 900×600. Sizes come from the window.
- The same reading sits in the same place in every ride type.
- Status never by colour alone. Text contrast ≥ 4.5:1.

## Decided by the owner (2026-11-13)

- Font: **Tektur** (SIL OFL 1.1) by default, digits at width 85; the font can be changed
  in Settings (Tektur, SF Rounded, System).
- Power shows an average over **3 s (default), 10 s, 30 s or 60 s**. No "instant" option.
  The window can be changed on the ride screen itself: the "Power · 3 s" caption is a button
  with a menu of the four windows (same stored setting as in Settings).
- No "on target" bar or text in the power tile. The target sits under the power number.
- Sound before each step: yes.
- Skip step: clicking the cyan **Next** tile skips to that step. No separate button.
- Chaindance: off by default (plan 10), no work on it.
- **Zone colours (workout screen only), decided without a mockup; the mockups still show the
  fixed cyan Next tile and lime target, and this paragraph wins where they differ:**
  - The **Next** tile takes the colour of the next step's power zone from the workout profile
    (same palette as the profile strip). The fast-forward icon and the top-right duration stay.
  - In the **power** tile only the *target* takes the current step's zone colour. The 3 s power
    number stays white.
  - **Heart rate moves from pink to red** (the colour of the heart-rate line), because threshold
    and VO2max are pink in the zone palette. Do this on every ride screen so heart rate has one colour.
  - Sweet spot is close to the lime accent; accept that, no special case.
  - FTP test keeps lime/cyan, free ride keeps lime. No zone colours there.
  - Contrast: text on a zone-coloured tile must keep at least 4.5:1; pick dark or white text per zone.
  - Report these as intended deviations from `1-workout.html` in the wrap-up.

## The layout

A header, two hero tiles, three reading tiles, one strip. The FTP-test column below is the
warm-up and cool-down layout; **during the ramp the FTP test uses the focus layout** in the
next section.

| Slot | Workout | FTP test | Free ride |
|---|---|---|---|
| Header | minimise · kind pill · title · device dots · clock · Pause · Stop & save · ⋯ | same, without Pause | kind pill, then an **ERG / Resistance** switch in place of the title |
| A · Power | "Power · 3 s" button (opens the window menu); top right an **intensity stepper** − 100 % + in 1 % steps; power; under it "Target 225 W" | no stepper; power; target under it | stepper −5 / +5 W (ERG) or − Level 4 + (resistance); power; target (ERG) or level under it |
| B · Time | step time left; under it the step name ("Sweet spot 2 of 3") and the step progress bar. No "4 of 7" | warm-up: "Ramp starts in" with the time, "Warm-up · spin easy" and a progress bar; cool-down: time left | ride time; under it kJ and simulated km |
| C | heart rate, nothing else in the tile | heart rate | heart rate, "Avg 128" in the top right corner |
| D | cadence | cadence | cadence, "Avg 89" in the top right corner |
| E | **Next**: next target in W, and only the next step's duration ("5:00") in the top right corner; no other text. The whole tile is the skip button ("Last step" and not clickable on the last one) | warm-up: **First step** 100 W with "+5 W / 12 s" in the top right corner; cool-down: Best 60 s | average power, "NP 184" in the top right corner |
| F · Strip | workout profile, finished steps dimmed, cursor, the **heart-rate line** over the bars, and in a lane **below** the bars the **average heart rate of every finished step** (heart icon and number only, "♥ 141", centred under its step); "37:18 ridden · 28:42 to go"; More metrics button | the three test phases as one bar: "Warm-up · 10:00" filling, "Ramp · until you stop" (no end shown), "Cool-down · 3:00" | power (with the target dashed) **and heart rate** of the last 10 min, each on its own scale, with a legend; More metrics |

Sizes at 1470×920: header 60, hero row 372, reading row 252, strip the rest (144), 16 pt gaps,
24 pt side padding. Hero digits 220 pt, reading digits 185 pt (≈ 25 mm), target 76 pt,
captions 30 pt, tile radius 32. Every reading tile has two rows only: the caption row with an
optional corner text (30 pt), and the number centred in the rest. No text under the number. Everything scales with `min(width / 1470, height / 920)`.

## FTP test during the ramp: the focus layout (`2-ftp-test-ramp.html`)

Why it differs: the last 3–4 minutes of a ramp get harder every step, the last minute is
all-out, heart rate nears its maximum and some riders get blurred or narrowing vision. The
rider can then take in two or three large shapes in a short glance, not captions. In ERG the
one thing he controls is cadence (the trainer sets the load, and the ramp ends below 45 rpm),
so cadence gets the same size as power. The whole 13" screen spans only about 8° at 2 m, so
position matters less than size, contrast and the number of things shown.

The layout switches at the phase change only (warm-up → ramp, ramp → cool-down), never in the
middle of the effort, and nothing moves during the ramp.

| Row | Content | Size at 1470×920 |
|---|---|---|
| Header (60) | minimise, kind pill, protocol, Hold to finish, Stop & save, ⋯. No clock, no device dots (a device problem shows as a banner) | as elsewhere |
| Row 1 (440) | **Power** (3 s, target under it) and **Cadence** (under it a gauge 0–120 rpm with a red zone below 45, amber 45–60, a round marker, and "ends below 45") | digits 300 pt ≈ 41 mm; target 84 pt |
| Row 2 (250) | **Heart rate** (one third, "Max 171" in the corner) and **Next step** (two thirds: "+5 W", seconds left, and the 12 segments at 32 pt height) | digits 150 pt ≈ 20 mm |
| Footer (rest) | "Ramp time 7:28", "Best 60 s 272 W", "Stop pedalling to finish" | 28 pt, meant for the early minutes |

States, all as whole-tile changes that read even when blurred (never colour alone: the
caption changes too, and nothing blinks faster than once a second; Reduce Motion: no pulse):
- cadence below 60 rpm: the cadence tile fills amber with dark digits, caption "Speed up";
- cadence below 45 rpm (the existing 5 s auto-finish window): the tile fills red and the
  gauge is replaced by "Ramp ends in 3" counting down; back to normal if cadence recovers;
- every step up: the segment bar empties and the target pulses once;
- no fresh power or cadence: "—" and "No signal" in the tile, as elsewhere.

Sound (same "Sound" setting as the workout cue, never a beep per step): one low tone when
cadence drops below 60 and a repeating tick during the 5 s auto-finish window, because
hearing still works when vision narrows.

Not shown on purpose: a marker for the power that would match the current FTP. It would
anchor the rider to stop there; the rule "the ramp never shows an end" stays.

**More metrics** (workout and free ride; not during the FTP ramp, `3b-free-ride-more-metrics.html`): the button in the strip
swaps the chart for one row of eight small readings (normalized power, max power, work, kcal,
simulated speed and distance, balance, max heart rate; trainer power when a meter is the
source) and a "Chart" button to go back. Nothing else moves. Key `M`, also in the ⋯ menu.
The choice is remembered.

**Intensity stepper (workout):** − and + change the intensity by 1 % (today's buttons do 5 %),
from 50 to 150 %. ↑/↓ do the same; ⇧↑/⇧↓ change by 5 %. The target under the power number
follows at once. Use the engine's existing intensity change with a step of 1; the limits and
what is recorded stay as they are.

**Free ride:** ERG steps are **5 W** (today 10 W); ⇧↑/⇧↓ change by 25 W. The ERG / Resistance
switch changes mode during the ride through the engine's existing transition (the same call
the pre-flight uses for each kind); it is disabled with "Trainer doesn't offer resistance"
when `model.resistanceLimits` is nil, and while a transition is running. If the engine cannot
switch mode in a running ride today, add that in `Sources/` with tests (release ERG, set the
level, record an event) and report it; do not fake it in the view.

**Skip step:** one click on the Next tile, no confirmation (the owner considers a click
during a ride intentional). The tile is a real button with the accessibility label
"Next: Recovery, 125 watts, 5 minutes. Skip to it now"; keep the identifier of today's skip
button. ⌘→ stays.

States (all in the same tiles, nothing moves):
- **Waiting:** slot B shows "Start pedalling".
- **Paused / auto-paused:** slot B turns amber with a pause glyph, the strip shows one line,
  "Paused · pedal to resume" (merge the two current hints), Pause becomes Resume.
- **FTP test:** see the focus layout above for the ramp states.
- **Last 10 s of a workout step:** slot E fills cyan; beeps at 3, 2, 1 s when the sound is on.
- **Target change:** the target pulses for 2 s (no pulse with Reduce Motion).
- **No fresh signal:** the tile shows "—" and an amber "No signal" caption with an icon.
- **Meter as source:** "Trainer 194 W" beside the target in A.
- **Debug / mock:** the existing "Debug · mock sensors" chip sits in the header.
- **Finishing:** "Confirming trainer stop…" replaces the strip text.

## Steps

1. **Font.** Add the Tektur variable TTF and `OFL.txt` under `App/Resources/Fonts/`
   (from `github.com/google/fonts`, `ofl/tektur`; ask the owner if the download is blocked).
   Register it: `ATSApplicationFontsPath` in `App/MacInfo.plist`, `UIAppFonts` in
   `App/Info.plist`, copy the folder in `Tools/package_preview.py` (the `dist` build) and
   regenerate the project. One helper, `Font.ftp(_ size:, weight:, width:)`, reads the
   `appFont` setting (`tektur` default, `sfRounded`, `system`) and falls back to SF Rounded if
   the font file is missing. No view names a font directly. `DashboardMetrics` is tested with
   the widest of the three so nothing clips after a switch.
2. **Domain rules** (`Sources/FTPunkDomain`, Swift Testing tests for each):
   - `LivePower.average(samples:at:window:)`: time-weighted mean of the last 3, 10, 30 or 60 s
     of power samples, zeros counted, paused time excluded, `nil` when the newest sample is
     older than 2 s. With less history than the window it averages what exists. Display only:
     recording, scoring, MAX 60 S, auto-pause and power matching keep their inputs.
   - `StepHeartRate.averages(session:)`: the average heart rate of every finished workout step
     (paused samples excluded, `nil` for a step without heart-rate data).
   - `DashboardMetrics.make(width:height:accessibilitySize:compact:)` → the scale and every
     size above; tests: 1470×920 gives 220 / 185 / 30, 900×600 fits without clipping, sizes
     never fall below hero 96 / reading 64 / caption 15, heights never exceed the height.
   - `DashboardSlots.make(kind:phase:…)` → what each slot shows per the table (replaces the
     block lists in `CockpitLayout`; keep `CockpitLayout` only for the Chaindance Large view).
   - `StepCue.due(remaining:previous:)` → fires once each at 3, 2 and 1 s before a step ends.
3. **Tokens and parts** (`App/DesignSystem/RideStyle.swift`, new): colours from the mockups
   (ground `#0d0c15`, tile `#191827`, raised `#232235`, text `#f3f4f8`, dim `#a9a9bf`, lime
   `#c5f74d`, heart `#ff7ab8`, next/best `#5fd9e8`, warning `#fcb852`), `DashTile`,
   `DashNumber`, `DashCaption`, `DashStepper`, `SegmentCountdown`, `DashHeader`. Zone colours
   stay `ZonePalette`. Add the colour pairs to the contrast tests.
4. **`RideDashboard`** (`App/Features/Ride/RideDashboard.swift`, new): a `GeometryReader` grid
   of the slots, no `ScrollView` on Mac, always dark. On compact width (iPhone) the same tiles
   stack A, B, C+D, E, F and may scroll; iPhone sizes follow Dynamic Type as today.
5. **Workout:** `WorkoutCockpitView` fills the slots and drops `ChaindanceBox`, `mainRow`,
   `readingsRow`, `profileBlock` and the footer. Intensity stepper in A, the Next tile as the skip button in E, the
   per-step heart-rate averages above the profile in F (`WorkoutProfileChart` gets an optional
   labels row). Keep every shortcut, accessibility identifier and VoiceOver label and value.
6. **Free ride:** same view; ERG / Resistance switch in the header, 5 W steps, level stepper,
   heart rate in the strip chart (`LivePowerChart` gets an optional heart-rate series), the
   averages in the tile corners.
7. **FTP test:** `FTPCockpitView` uses the standard slots in warm-up and cool-down
   (`PhaseTimeline` becomes the strip) and the focus layout during the ramp (the countdown
   ring becomes the 12 segments; the coaching line and notes go, except the footer line).
   Put the cadence state (normal / speed up / ending in n s) in a pure rule in `Sources/` with
   tests, reading the engine's existing low-cadence timer; do not add a second timer or change
   the 45 rpm / 5 s rule. `HoldToConfirmButton` (⌘⇧F) sits in the header. The Chaindance Large view keeps the current code path; the strip placement
   takes slot F.
8. **More metrics** in the strip as described, reusing the values of `RideMoreReadings`.
9. **Settings → Ride screen** (`design/app-redesign/6-settings.html`): "Power average:
   3 s / 10 s / 30 s / 60 s" (`ridePowerWindow`, default 3), "Number size: Fit to screen /
   Compact" on Mac (the existing "Extra-large ride numbers" stays for iPhone), "Sound before
   each step" (default on), Chaindance toggle with "Off by default".
10. **Sound:** play a short system sound when `StepCue` fires in workouts (not while paused),
    and the two cadence sounds of the FTP ramp. One setting switches all of them.
11. **Menu bar:** the Ride menu from plan 10 gains the 1 % / 5 % and 5 W / 25 W items and
    "More metrics".
12. **Preview scenarios:** `dash-workout`, `dash-workout-countdown`, `dash-workout-paused`,
    `dash-workout-scaled`, `dash-ftp-warmup`, `dash-ftp-ramp`, `dash-ftp-low-cadence`, `dash-ftp-ending`, `dash-ftp-cooldown`, `dash-free-ride`,
    `dash-free-ride-resistance`, `dash-more-metrics`, `dash-signal-lost`; add them to
    `ShellAndScenarioTests.scenarioNamesMatchThePlan` and to the Mac walkthrough at 1470×923.
13. **Wrap-up:** README (cockpit paragraphs, shortcuts, 5 W and 1 % steps), roadmap "Where it
    stands", move this file to `docs/archive/`, rebuild `dist/FTPunk.app` (only while it is
    not running).

## Done

`swift test` passes and both CI builds pass. Then ask the owner for the visual review:
the scenarios in full screen on the Air, looked at from the bike. Report anything in
"Free ride" that needed an engine change.

## Not in this plan

Chaindance scenes, the web app (park "web port of the ride dashboard" in the roadmap),
an Undo for Skip step.
