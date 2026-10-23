# UI review and implemented refinements

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
- Cadence and optional heart rate are secondary, readable metrics. Missing/stale power or cadence displays a dash, rather than an old value as if it were current.
- The power trace remains below the key metrics. Signal gaps break the line. Cadence can come from the external meter or trainer; without cadence, a clearly labeled manual-finish mode preserves power-only testing.
- Finish ramp and Stop/save are separate actions pinned below the scrollable dashboard; immediate stop requests confirmation. Mock controls are collapsible and clearly marked.
- The completed result replaces the live tiles. The range is explicitly labeled 72–77%, and the explanation is one tap away.

No live FTP prediction is presented while the rider is still testing: it would be a provisional number that can distract from the prescribed effort. Audio cues and target-versus-measurement overlays remain future refinements.

## Progress and deletion

History groups recordings by stable rider ID, with a person filter and FTP/W/kg chart. Profile renames update group headings while each recording retains its original rider-name and weight snapshots. Each point is one test; the chart separates riders and real/debug series. Debug results are excluded by default and marked with diamonds when included. Comparisons should use matching protocols, factors and power sources.

Delete is visible in each row and in activity details, with swipe and context-menu access as alternatives. Confirmation explains that local samples and pending jobs are removed, while already uploaded activities and explicitly adopted FTP settings remain. Deleting the latest result also clears it from the Ride tab.

## Appearance and desktop use

System, Light and Dark settings persist on each device. Semantic system surfaces and text adapt to the selected theme, with a dark green accent in light mode and a lime accent in dark mode. Controls use native platform styles, large primary actions and accessibility labels.

The native Mac app shares domain logic and SwiftUI screens, supports resizing and persistent local history, and keeps the Mac awake during a test. It has a dedicated Xcode scheme, Bluetooth/network sandbox entitlements for signed builds, and a local app/ZIP packaging script. Local macOS and iOS data remain independent pending future server sync.

## Intervals.icu

API-key access is available to all users in Settings, independently of mock mode. OAuth remains the preferred future sign-in path once the app is approved. Keychain stores either credential type. Every new upload requires confirmation naming both the rider and the destination athlete account. Already approved queued activities retain their retry behavior; old unapproved automatic jobs are cancelled when the prototype migrates. No remote FTP or weight is changed.

## Verification boundary

Automated tests additionally cover trainer-only FTMS recordings, selected-source isolation, loss without silent fallback, independent field freshness, power-only manual finishing and source metadata/export migration. They also cover rider migration, independent profile storage, grouped identity, historical snapshots, correct-rider FTP adoption, local deletion, consent without sending, rejection after an account switch, mock exclusion, and 20 W/60 s boundaries and limits. The native Mac walkthrough renders setup, protocol, readiness, dashboard, results, progress and settings in dark mode, plus light settings/results. The iOS and native macOS Xcode schemes build successfully. The app also runs on the iOS 27.1 virtual iPhone in Xcode 27 Device Hub; its light dashboard and pinned actions were checked on the active display. Live trainer/pedal validation, real account upload, larger Dynamic Type, VoiceOver traversal and a wider set of physical display sizes remain release work.
