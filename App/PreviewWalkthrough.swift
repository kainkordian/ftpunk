#if os(macOS)
import AppKit
import Foundation

/// Captures only this app's own view, without accessing the desktop or other apps.
@MainActor enum PreviewWalkthrough {
    static func run(model: AppModel) async {
        guard ProcessInfo.processInfo.arguments.contains("--preview-walkthrough") else { return }
        let directory = URL(fileURLWithPath: "/tmp/ftpunk-preview")
        let previousAppearance = UserDefaults.standard.string(forKey: "appearance")
        defer {
            if let previousAppearance { UserDefaults.standard.set(previousAppearance, forKey: "appearance") }
            else { UserDefaults.standard.removeObject(forKey: "appearance") }
        }
        do {
            UserDefaults.standard.set("dark", forKey: "appearance")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await Task.sleep(for: .seconds(1))
            if let window = NSApplication.shared.windows.first {
                window.setContentSize(NSSize(width: 520, height: 900)); window.center()
            }
            model.selectedTab = 0
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("setup.png"))
            model.setupStep = 1
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("protocol.png"))
            model.setupStep = 2
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("ready.png"))
            model.mockSpeed = 4
            await model.start()
            try await Task.sleep(for: .seconds(1))
            model.skipMockWarmup(); model.advanceMock(seconds: 75); model.mockPaused = true
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("ride.png"))
            model.advanceMock(seconds: 600)
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("result.png"))
            model.selectedTab = 2
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("history.png"))
            model.selectedTab = 3
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("settings.png"))
            UserDefaults.standard.set("light", forKey: "appearance")
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("settings-light.png"))
            model.selectedTab = 1
            try await Task.sleep(for: .seconds(1))
            try capture(to: directory.appendingPathComponent("result-light.png"))
            // Leave the completed ride on screen so its result and charts can be inspected.
            model.selectedTab = 1
        } catch {
            model.errorMessage = "Preview capture failed: \(error.localizedDescription)"
        }
    }
    private static func capture(to url: URL) throws {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }), let view = window.contentView,
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
