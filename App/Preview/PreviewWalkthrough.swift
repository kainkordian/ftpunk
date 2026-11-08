#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import FTPunkDomain

/// Screenshot matrix for the isolated preview: every scenario in dark and light, at the default and an
/// accessibility text size, in a 393 × 852 iPhone-sized layout, plus the Mac window.
/// Captures only this app's own views, without accessing the desktop or other apps.
///
///     swift build && Tools/run_preview.sh --preview-walkthrough            # every scenario
///     Tools/run_preview.sh --preview-walkthrough --scenario ride-ramp      # one scenario
///     add --capture-dir <path> to choose the folder, --exit-after-capture to quit when done
@MainActor enum PreviewWalkthrough {
    static func run(model: AppModel) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--preview-walkthrough") else { return }
        let directory = URL(fileURLWithPath: value(after: "--capture-dir", in: arguments) ?? "/tmp/ftpunk-preview")
        let previousAppearance = UserDefaults.standard.string(forKey: "appearance")
        defer {
            if let previousAppearance { UserDefaults.standard.set(previousAppearance, forKey: "appearance") }
            else { UserDefaults.standard.removeObject(forKey: "appearance") }
            model.previewPhoneLayout = false; model.previewTextSize = nil
            // A sheet left open can keep terminate(_:) from finishing, so close them and leave directly.
            if arguments.contains("--exit-after-capture") { model.builder = nil; model.uploadConsent = nil; exit(0) }
        }
        let scenarios = PreviewScenario.requestedList(arguments: arguments)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await Task.sleep(for: .seconds(1))
            for scenario in scenarios.isEmpty ? PreviewScenario.allCases : scenarios {
                try await PreviewScenarios.apply(scenario, to: model)
                for appearance in ["dark", "light"] {
                    UserDefaults.standard.set(appearance, forKey: "appearance")
                    for (label, size) in [("default", nil), ("accessibility", Optional(DynamicTypeSize.accessibility3))] {
                        model.previewPhoneLayout = true; model.previewTextSize = size
                        resize(width: 393, height: 852)
                        try await Task.sleep(for: .milliseconds(900))
                        try capture(to: directory.appendingPathComponent("\(scenario.rawValue)-\(appearance)-\(label).png"))
                    }
                }
                UserDefaults.standard.set("dark", forKey: "appearance")
                model.previewPhoneLayout = false; model.previewTextSize = nil
                resize(width: 900, height: 820)
                try await Task.sleep(for: .milliseconds(900))
                try capture(to: directory.appendingPathComponent("\(scenario.rawValue)-mac.png"))
                if scenario == .workoutDetail {
                    for appearance in ["dark", "light"] {
                        try captureView(WorkoutDetailSheet(model: model, ref: .classic("vo2max-5x3")), dark: appearance == "dark",
                                        width: 520, height: 1100, to: directory.appendingPathComponent("workout-detail-sheet-\(appearance).png"))
                    }
                }
            }
            try captureStrips(to: directory)
        } catch {
            model.errorMessage = "Preview capture failed: \(error.localizedDescription)"
        }
    }
    private static func value(after flag: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
    private static func resize(width: CGFloat, height: CGFloat) {
        if let window = NSApplication.shared.windows.first {
            window.setContentSize(NSSize(width: width, height: height)); window.center()
        }
    }
    /// Chaindance on its own, at a few efforts, so the artwork can be reviewed without a whole screen.
    private static func captureStrips(to directory: URL) throws {
        let ramp = RideVisualInput.Ramp(phaseSeconds: 360, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 360, bestMinuteWatts: 290)
        func step(_ index: Int, watts: Double, remaining: Double, next: Double? = nil) -> RideVisualInput.Step {
            .init(index: index, count: 11, startWatts: watts, endWatts: watts, seconds: 180, remaining: remaining,
                  next: next.map { .init(seconds: 180, startWatts: $0, endWatts: $0) })
        }
        let inputs: [(String, RideVisualInput)] = [
            ("recovery", .init(mode: .workout, phase: .riding, power: 110, cadence: 85, ftp: 250, step: step(2, watts: 125, remaining: 90))),
            ("endurance", .init(mode: .workout, phase: .riding, power: 165, cadence: 88, ftp: 250, step: step(0, watts: 165, remaining: 90))),
            ("tempo", .init(mode: .ftpTest, phase: .ramp, power: 205, cadence: 90, ftp: 250, ramp: ramp)),
            ("sweet-spot", .init(mode: .ftpTest, phase: .ramp, power: 225, cadence: 90, ftp: 250, ramp: ramp)),
            ("threshold", .init(mode: .ftpTest, phase: .ramp, power: 250, cadence: 92, ftp: 250, ramp: ramp)),
            ("vo2max", .init(mode: .workout, phase: .riding, power: 288, cadence: 95, ftp: 250, step: step(3, watts: 288, remaining: 8, next: 125))),
            ("paused", .init(mode: .workout, phase: .paused, ftp: 250, step: step(3, watts: 288, remaining: 90))),
            ("summit", .init(mode: .ftpTest, phase: .cooldown, power: 120, cadence: 70, ftp: 250,
                             ramp: .init(phaseSeconds: 1, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 560, bestMinuteWatts: 290)))
        ]
        for (name, input) in inputs {
            var motion = RideVisualMotion()
            let state = RideVisualState.make(input)
            for _ in 0..<60 { motion.advance(by: 0.1, state: state) }
            let view = NSHostingView(rootView: RideVisualImage(scene: RideVisualScene(state: state, motion: motion, spriteRider: true))
                .padding().frame(width: 393, height: 160).background(Color.black).preferredColorScheme(.dark))
            view.appearance = NSAppearance(named: .darkAqua)
            view.frame = NSRect(x: 0, y: 0, width: 393, height: 160)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: directory.appendingPathComponent("ride-visual-\(name).png"), options: .atomic)
            }
        }
    }
    /// Renders one view off screen, for sheets that a scenario cannot open in the window.
    private static func captureView<Content: View>(_ content: Content, dark: Bool, width: CGFloat, height: CGFloat, to url: URL) throws {
        let view = NSHostingView(rootView: content.frame(width: width, height: height)
            .background(dark ? Color.black : Color.white).preferredColorScheme(dark ? .dark : .light))
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url, options: .atomic) }
    }
    /// The main window, and when a sheet is attached (builder, upload prompt, …) the sheet too, as `<name>-sheet.png`.
    /// A macOS sheet is its own window, so capturing only the parent's content leaves it out.
    private static func capture(to url: URL) throws {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) else { return }
        try capture(window: window, to: url)
        if let sheet = window.attachedSheet {
            let name = url.deletingPathExtension().lastPathComponent + "-sheet.png"
            try capture(window: sheet, to: url.deletingLastPathComponent().appendingPathComponent(name))
        }
    }
    private static func capture(window: NSWindow, to url: URL) throws {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // AppKit's window material stays transparent in a view-only capture.
        // Composite the captured view over the app's dark window background.
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        let mode = UserDefaults.standard.string(forKey: "appearance")
        let dark = mode == "dark" || (mode != "light" && window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        NSColor(calibratedWhite: dark ? 0.06 : 0.97, alpha: 1).setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size)
            .draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero,
                  operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        if let data = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            try png.write(to: url, options: .atomic)
        }
    }
}
#endif
