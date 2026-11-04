import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The text on the system clipboard, if any (for "Create workout from text").
enum Clipboard {
    @MainActor static func text() -> String? {
        #if canImport(UIKit)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}
