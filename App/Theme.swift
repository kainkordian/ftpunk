import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

enum Theme {
    static var accent: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.77, green: 0.97, blue: 0.30, alpha: 1)
                : UIColor(red: 0.12, green: 0.39, blue: 0.19, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.77, green: 0.97, blue: 0.30, alpha: 1)
                : NSColor(red: 0.12, green: 0.39, blue: 0.19, alpha: 1)
        })
        #endif
    }
}

extension View {
    @ViewBuilder func numberEntry() -> some View {
        #if canImport(UIKit)
        self.keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        #else
        self.multilineTextAlignment(.trailing)
        #endif
    }
}
