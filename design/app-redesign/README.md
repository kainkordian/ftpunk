# App redesign mockups (2026-11-13)

Static HTML mockups for plans 11 and 12 in `docs/next/`. Each file is one 1470×920 screen
(a 13" MacBook Air M2 in full screen). Open them in a browser; the font (Tektur) loads from
Google Fonts. They are the reference for layout, sizes, colours and wording: every size is an
inline pixel value at 1470×920, and the app scales them with the window.

| File | Screen | Plan |
|---|---|---|
| `1-workout.html` | Workout ride screen | 11 |
| `2-ftp-test-ramp.html` | FTP test during the ramp: the focus layout | 11 |
| `2b-ftp-test-warm-up.html` | FTP test in warm-up (cool-down uses the same layout) | 11 |
| `3-free-ride.html` | Free ride, ERG mode, chart strip | 11 |
| `3b-free-ride-more-metrics.html` | Free ride with "More metrics" open | 11 |
| `4-home.html` | Home | 12 |
| `5-ride-summary.html` | Ride summary (FTP test result) | 12 |
| `6-settings.html` | Settings, "Ride screen" section | 12 |

`png/` holds each screen rendered at 1470×920 with Tektur: the reference to compare the built
app against (see "Fidelity" in plans 11 and 12).

The numbers are sample values. The same boards live on the owner's private design canvas
"FTPunk · 2 m ride dashboard and app redesign"; if the two differ, the canvas is newer.

## Zone colours

`1-workout.html` (sweet-spot step, recovery next) and `1b-workout-recovery-step.html` (recovery
step, sweet spot next) show the zone-coloured Next tile and target. Heart rate is red on all
boards. Rules: `docs/next/11-ride-dashboard.md`, "Decided by the owner".
