# User preferences

## Visual checks

Ask the user for permission before starting a new visual review, including opening
native apps or browsers for inspection and capturing screenshots. An explicit
request to perform that review supplies permission for that review only; do not
carry it over to later reviews or sessions.

Code inspection, automated non-visual tests and builds do not require this visual
review permission. User permission does not override organization/tool access
restrictions: report those restrictions rather than working around them.

## Deferred device checks

Physical trainer/iPhone checks remain deferred; locked-screen iOS operation
is not required. The Miyoo companion and the background/browser host were scratched
on 2026-11-04. Don't plan or build them.

The Computer Use access-check reminder was delivered on 2026-11-02. Browser
inventory still reported “The browser access host is unavailable.” Native window
capture was not retried during that diagnostic; the earlier organization-policy
denial remains unverified. Keep the visual-review permission preference above.

# Working rules for agents

- Start with `docs/ROADMAP.md`. Work only on the plan you were given from `docs/next/`.
  When it's done, move it to `docs/archive/`, update the roadmap's "Where it stands" and
  report anything unverified.
- **Don't create new plan or status documents.** New ideas go into the roadmap's "Parked"
  list (one line) for the owner to decide. A ready-to-run plan is written only when the owner
  asks, and goes into `docs/next/`.
- The FTP test is the core feature. Don't change ramp scoring, the ramp protocol or the
  72 % estimate factor.
- Pure logic goes in `Sources/` with Swift Testing tests. SwiftUI views stay thin. New `App/` files
  are picked up by `Tools/generate_project.py`; regenerate the project.
- Done means `swift test` passes (use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  if `xcode-select` points at CommandLineTools) and both CI builds pass:
  `xcodebuild -project FTPunk.xcodeproj -scheme FTPunk -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  and `xcodebuild -project FTPunk.xcodeproj -scheme FTPunkMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- Don't commit unless the owner asks.
