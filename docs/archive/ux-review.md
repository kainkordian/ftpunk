# UI review and implemented refinements

> Design history. The setup flow, five-tab navigation and History screen described below were replaced by the [UX rework](ux-rework-plan.md) (Home, pre-flight, cockpit, result, Progress). The accessibility and readability review at the end still applies.

The original prototype exposed most settings in one long form. It showed the necessary data but asked a new rider to handle profile details, Bluetooth, protocol choices, diagnostics and account credentials at once. Its large power number lacked an equally clear target and next-step countdown. History was a flat list, with deletion relying on an undiscoverable swipe.

## Setup workflow

The implemented flow follows a familiar preparation → activity → result pattern:

1. **Rider:** choose or add a named local profile, check weight, and choose current, historical or manual FTP. Save the starting point before continuing.
2. **Protocol:** choose one of three descriptive ramp cards, review warm-up watts, and optionally change duration, target or estimate factor. Explanations open where a decision is made.
3. **Ready:** review the rider and test, connect the devices or enable mock input, then start using the persistent primary button.
4. **Ride:** concentrate on the next action, with settings and diagnostics outside the main dashboard.
5. **Result:** save locally, show FTP and W/kg, optionally adopt the estimate for the correct rider, and ask before any upload.

Back/Continue controls remain visible below the scrollable form. Advanced warm-up and debug settings use disclosure controls. The four persistent destinations are New test, Ride, Progress and Settings. A second local rider needs no account and does not inherit the first rider's weight or FTP. Trainer power is the default; an external Bluetooth power meter is explicitly optional on Ready. The UI explains that this means a separate pedal, crank or hub sensor.

## Ride dashboard

The rider's immediate questions are: what power should I hold, what am I actually producing, how long until the next increase, and can I keep pedaling steadily?

- Large, adjacent target and actual measured-power tiles distinguish prescription from measurement.
- A countdown and progress bar show the next increase, with the correct increment for each protocol. Each test displays its fixed power source. Ramp time and step number are separate from total activity time.
- Heart rate and cadence have large dedicated tiles directly beneath power, with a heart icon and distinct color for heart rate. Missing/stale signals display a dash, rather than an old value as if it were current.
- The power trace remains below the key metrics. Signal gaps break the line. Cadence can come from the external meter or trainer; without cadence, a clearly labeled manual-finish mode preserves power-only testing.
- Finish ramp and Stop/save are separate actions pinned below the scrollable dashboard; immediate stop requests confirmation. Mock controls are collapsible and clearly marked.
- The completed result replaces the live tiles. The range is explicitly labeled 72–77%, and the explanation is one tap away.

The live MAX 60 S metric is measured average power, not a live FTP prediction. It waits for a complete fresh ramp minute, keeps the earlier best, and is rechecked against the exact final ramp endpoint. Its info sheet explains the distinction. Optional audio/haptic step cues remain future refinements.

Manual FTP now has a prominent, bordered numeric field with an explicit watts label and warm-up explanation. Warm-up and cool-down each use clearly bordered numeric fields for 0–60 whole minutes, with visible units, range guidance, validation and a Done button on the iPhone keyboard, with zero skipping the phase. The Ready summary includes both effective durations, and the quick-debug override is explicit alongside the controls. Optional Stelvio pixel scenery uses a procedural third-person road, snow-capped mountains, perspective markers, and a rear-view cyclist wearing the selected icon's magenta helmet and lime jersey. It loops indefinitely during the ramp, reaches the summit only at the real ramp ending, then descends during recovery. Skipped recovery keeps the summit. Interrupted ramps show a stopped scene. The pixel-ride layout compacts the metric tiles for iPhone 15 Pro; the toolbar can switch modes during a test. Reduce Motion freezes the image while preserving phase changes, and VoiceOver receives a phase-specific scene description.

At automatic exhaustion, the hardware path now releases ERG and continues recording the selected free-spin recovery. No cool-down target is sent in this mode. A manually finished ramp still uses its gentle target. The FTP window ends before recovery, so descent readings never change the score. Missing telemetry or a failed stop confirmation ends recovery while preserving an already-scored ramp. Verify continued telemetry and stop acknowledgements on real trainer firmware before release.

## Progress and deletion

History groups recordings by stable rider ID, with a person filter and FTP/W/kg chart. Profile renames update group headings while each recording retains its original rider-name and weight snapshots. Each point is one test; marker shapes and legend labels separate riders and real/debug series. Debug results are excluded by default. Comparisons should use matching protocols, factors and power sources.

Delete is visible in each row and in activity details, with swipe and context-menu access as alternatives. Confirmation explains that local samples and pending jobs are removed, while already uploaded activities and explicitly adopted FTP settings remain. Deleting the latest result also clears it from the Ride tab. Trend charts now distinguish rider and real/debug series using marker shapes and explicit legend labels as well as color; dated values remain available in the grouped list.

## Accessibility and readability review

For a riding dashboard, viewing distance, effort and sweat make legibility and simple controls useful beyond diagnosed vision or motor impairments. The implementation follows [Apple's accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) on scalable text, contrast, alternatives to color and motion preferences. Primary action palettes are tested against the [WCAG 4.5:1 normal-text contrast threshold](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum).

- **Contrast:** explicit opaque primary-button palettes fix white-on-lime labels across setup, start, upload and result actions. Native segmented controls/switches use a darker green with readable white content. Destructive ride controls use a labelled high-contrast outline; warning and secondary text use stronger opaque inks. Increased Contrast adds stronger telemetry outlines.
- **Low vision:** baseline ride numbers are larger; an extra-large option and system Dynamic Type scale them further. At accessibility sizes, metrics/actions stack vertically, the ride header simplifies, and the theme picker becomes a menu. Explanations use larger footnote text. More content can require scrolling; the essential finish/stop controls remain pinned.
- **Color-vision differences:** every metric has a name, icon and unit. Protocol selection has a checkmark; chart series have marker shapes, legend names and a dated results list. No sensor status or result depends on green/red alone, so a separate simulated-color palette is unnecessary for understanding the UI.
- **VoiceOver:** telemetry is grouped with clear names/values, the 60-second metric explains its provisional window, iPhone phase changes are announced once at transitions, and charts have labels/list alternatives. Values are available on demand instead of narrating every sensor notification. The version bubble is a real button with an activation countdown, allowing ten VoiceOver/Switch Control/keyboard activations to unlock debugging.
- **Motion:** Reduce Motion freezes the pixel scene and shows the raised-arm victory pose without bobbing. There are no flashing celebration effects. The uphill panorama uses an elevated crest, visible valley and exposed road edge to communicate climbing.
- **Motor/cognitive use:** primary buttons and deletion targets are at least 44 points; stop/finish stay reachable, native controls retain keyboard navigation, setup stays staged, and debug controls are hidden until explicitly unlocked. Unlocking never switches an active real recording to mock input.

The practical next accessibility work is hands-on VoiceOver rotor/traversal and Switch Control testing, a broader physical-device/display matrix, and rider-controlled optional step sounds/haptics. The app does not claim an accessibility certification from screenshots or unit tests alone. Normal-size light/dark iPhone 15 Pro layouts, the largest Dynamic Type category with Increase Contrast, and the Mac walkthrough are included in visual QA. The test suite covers primary/native-control text contrast, unlock boundaries, active-source protection, live coverage/zeros and exhaustion-endpoint rescoring.

## Appearance and desktop use

The primary iPhone UI target is the user's **iPhone 15 Pro**, at 393 × 852 points in portrait. Review light and dark modes at that size before expanding the device matrix. `Tools/run_simulator.sh` requires that exact model and selects only a runtime that explicitly supports it; it does not substitute another iPhone. The unused Duo simulators and iOS 27.1 runtime were removed from the development Mac. iOS 27.0 provides the compatible simulator runtime.

System, Light and Dark settings persist on each device. Semantic system surfaces and text adapt to the selected theme, with a dark green accent in light mode and a lime accent in dark mode. Controls use native platform styles, large primary actions and accessibility labels.

The native Mac app shares domain logic and SwiftUI screens, supports resizing and persistent local history, and keeps the Mac awake during a test. It has a dedicated Xcode scheme, Bluetooth/network sandbox entitlements for signed builds, and a local app/ZIP packaging script. Local macOS and iOS data remain independent pending future server sync.

## Intervals.icu

API-key access is available to all users in Settings, independently of mock mode. OAuth UI is hidden for now; its implementation remains available for a future sign-in path once the app is approved. Keychain stores either credential type. Every new upload requires confirmation naming both the rider and the destination athlete account. Already approved queued activities retain their retry behavior; old unapproved automatic jobs are cancelled when the prototype migrates. No remote FTP or weight is changed.

## Verification boundary

Automated tests additionally cover trainer-only FTMS recordings, selected-source isolation, loss without silent fallback, independent field freshness, power-only manual finishing and source metadata/export migration. They also cover rider migration, independent profile storage, grouped identity, historical snapshots, correct-rider FTP adoption, local deletion, consent without sending, rejection after an account switch, mock exclusion, custom/zero warm-up and cool-down durations, and 20 W/60 s boundaries and limits. The native Mac walkthrough renders setup, protocol, readiness, dashboard, results, progress and settings, plus light-theme screens and optional Stelvio scenery. The iOS and native macOS builds succeed. The app runs on the iPhone 15 Pro simulator with iOS 27.0; target/actual power, heart rate, cadence, the next-step countdown and pinned finish/stop actions fit together in portrait at the standard text size. Live trainer/pedal validation, real account upload, larger Dynamic Type, VoiceOver traversal and a wider set of physical display sizes remain release work.

## Form interaction review

Disclosure headers respond across the full row, including the label, whitespace and trailing chevron. This covers debug options, the power trace, custom warm-up, API-key access and Bluetooth diagnostics. Toggle rows also have one full-row action and retain native switch accessibility through an accessibility representation; tapping the switch cannot toggle twice. Form actions, selection menus and device rows have 44-point targets. History trash hit areas are inside the button label so their padding is clickable without extending deletion over the neighboring history link. Debug actions stack at accessibility text sizes.

Duration inputs accept an editable draft and update the effective minutes only for a whole number from 0 through 60. Invalid or empty drafts show guidance and block Continue; quick-debug timing explicitly replaces the fields with its 10-second override. The external meter always has its own optional device row alongside Trainer and Heart rate. Connecting a meter selects its power; deliberately disconnecting it returns to trainer power before a new test. The source selector remains explicit, and active-test source isolation is unchanged.

Implementation references: [SwiftUI disclosure styles](https://developer.apple.com/documentation/swiftui/disclosuregroupstyle) and [accessibility representations](https://developer.apple.com/documentation/swiftui/view/accessibilityrepresentation(representation:)). Visual previews cover the revised protocol inputs, devices and settings on Mac; full-row gesture and assistive-technology behavior still need hands-on device validation.
