# 01 — Settings: devices, power matching, API key, credits

## Problems found on macOS

1. Power matching appears in three places: a toggle in Settings → "Devices & trainer
   control", the "Measure power with" picker in `DevicesSheet`, and a read-only
   "Power matching On/Off" row in `DevicesSheet`. It's unclear which one is in charge.
2. Device pairing hides behind one plain row, "Trainer, power meter and heart rate…".
   It doesn't look like the place where you connect devices, even though a trainer is
   required to ride.
3. The Intervals.icu API key `SecureField` can't be recognised as an input on macOS.
   In a `.grouped` Form on macOS a bare `SecureField` renders as borderless text.
4. The About credits mention only the owner and OpenAI Codex.

## Files

- `App/Features/Settings/SettingsView.swift`
- `App/Features/Home/DevicesSheet.swift`
- `App/AppInfo.swift`
- `App/Features/Shell/ContentView.swift` (power-matching alert text names a settings path)
- Possibly a new `App/DesignSystem/DeviceStatusRow.swift`

## Target design

### Settings → "Devices" section (first section after Riders, or first overall)

Rename the group from "Devices & trainer control" to **"Devices"**. Replace the single
button and the toggle with three always-visible rows, one per role, built from a shared
`DeviceStatusRow` view:

| Row | Badge | Subtitle when not connected | Subtitle when connected |
|-----|-------|-----------------------------|-------------------------|
| Smart trainer | **Required** (warning tint when missing) | "Required to ride · tap to connect" | device name + "ERG ready" / status |
| Power meter | Optional | "Optional · for power matching or as the power source" | device name |
| Heart rate monitor | Optional | "Optional" | device name |

- Each row has an icon (`bicycle`, `bolt.circle`, `heart.circle`), a coloured status dot
  (green connected, orange required-but-missing, grey optional-and-missing) and a chevron.
- Tapping a row opens `DevicePicker` for that role directly (reuse it; it's already a
  sheet). Keep a secondary "Measurement & trainer control…" row that opens `DevicesSheet`.
- Section footer: "A smart trainer with ERG control is required. A power meter and a
  heart rate monitor are optional."
- **Remove** the `Toggle("Power matching", …)` from this section.
- In mock/debug mode, show the existing "Mock sensor stream" notice instead of the rows.

Move the role-row view out of `DevicesSheet` into `DeviceStatusRow` so Settings and the
sheet render the same row.

### DevicesSheet: one home for power source + matching

Replace the "Measurement" section with a single power control, shown **only when a power
meter is connected**:

```
Power source
  ( ) Trainer
  ( ) Power meter — trainer follows the meter (power matching)   ← default when a meter is connected
  ( ) Power meter — record only, no matching
```

- Implement as one picker over a small app-level enum (e.g. `PowerMode { trainer,
  meterMatched, meterRecordOnly }`) that maps onto the existing `model.powerSource` and
  `model.powerMatchingEnabled`. Don't change `SessionConfiguration`; the session
  snapshot still gets `powerSource` + `powerMatchingEnabled`.
- Without a meter, show one line instead: "Power: measured by the trainer".
- Keep the cadence row. Footer: "Fixed when a ride starts."
- Delete the read-only "Power matching On/Off" row.
- Keep the "Learn more" power-matching topic. Link it from this section.
- Update the alert copy in `ContentView.swift` ("Your choice is saved in Settings →
  Devices & trainer control") so it names the new place: "Settings → Devices → Power
  source".
- `DevicePicker` already sets `powerSource = .externalPowerMeter` when pedals connect.
  Keep that behaviour. The first-connect alert (`powerMatchingPrompt`) still decides
  between matched and record-only.

### API key field (macOS)

In `intervalsSection`:

```swift
LabeledContent("API key") {
    SecureField("Paste your personal API key", text: $model.apiKeyInput)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 220)
        #if os(iOS)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        #endif
}
```

- Add a "Paste" button next to it on macOS (`NSPasteboard.general.string(forType: .string)`)
  and on iOS (`PasteButton`), since keys get pasted, not typed.
- Make "Connect with API key" a `.borderedProminent` button so it looks actionable.
- If the OAuth sign-in button (`App/IntervalsSignIn.swift`) appears in this section, check
  that it's equally visible on macOS.

### Credits

`App/AppInfo.swift`:

```swift
static let credits = "Created by Kordian Gontarska · Developed with OpenAI Codex and Anthropic Claude"
```

Check for any test or accessibility string that asserts the old credits text
(`grep -rn "OpenAI Codex" App Tests`) and update it.

## Tests

- Unit test for the `PowerMode` ↔ (`powerSource`, `powerMatchingEnabled`) mapping in
  both directions, including "meter disconnected → trainer".
- Existing `PowerSourceTests` / `PowerMatchingTests` must stay green.
- Both CI builds (the macOS one matters here: `LabeledContent`/`NSPasteboard` code paths).

## Out of scope

Changing the power matcher's control loop (see plan 06).
