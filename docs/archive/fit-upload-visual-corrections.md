# Corrections after the visual check of FIT uploads and ride extras

Owner asked for corrections to be planned if the visual check found problems (2026-11-09). All four are in the web app; the native views looked right.

1. **Heart-rate chart label collides with the top tick.** In `heartRateChart` (`ftpunk_web/src/ui/charts.mjs`) the "bpm" title and the highest tick label share the top-left corner and overlap, at any window width. Give the title its own row above the plot, as the "W" title has on the power chart, for every heart-rate range. Keep the chart's width and the time axis as they are.
2. **Balance tile wraps.** `#live-balance` ("50 / 50") breaks over two lines in the cockpit's five-across row and at phone width, where the tiles are three across (`.support-tiles`, 390 px window). It must stay on one line with its "L/R" unit inside the tile at both, with no clipping. Scope the change to this tile; other tiles keep their size. Native already fits.
3. **Target legend swatch looks solid.** `.chart-legend .swatch.target` in `ftpunk_web/src/ui/result.css` renders as a solid line while the target line on the chart is dashed. Make the swatch visibly dashed in light and dark, as the native legend is.
4. **Pedal balance is lost through a web archive.** The sample whitelist in `ftpunk_web/src/archive.mjs` (`pick(m, [...])`) omits `leftBalance`, so an export or import drops it. Add it, validated like the native archive (finite, 0 to 100; check `PortableArchive.swift` and fix the native side too if it does not validate). Add a web test for the round trip and for a rejected out-of-range value.

## Done

- `swift test`, both `xcodebuild` CI builds from AGENTS.md and `CI=true python3 ftpunk_web/tools/test.py` pass.
- `ftpunk_web/sw.js` stays at v10: that version has not shipped.
- This plan moved to `docs/archive/`. The roadmap's "Where it stands" gets no new entry unless the archive fix changes what it says.
