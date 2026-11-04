import Foundation
import FTPunkDomain

/// Top-level destinations: tabs on iPhone, sidebar rows on Mac.
enum AppDestination: String, CaseIterable, Identifiable {
    case home, progress, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .home: "Home"; case .progress: "Progress"; case .settings: "Settings" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .progress: "chart.xyaxis.line"; case .settings: "gearshape" }
    }
}

/// A workout the rider can start: a built-in classic or an entry in the cached library.
enum WorkoutRef: Hashable, Identifiable {
    case classic(String)
    case cached(String)
    case custom(UUID)
    var id: String {
        switch self { case .classic(let id): "classic:\(id)"; case .cached(let id): "cached:\(id)"; case .custom(let id): "custom:\(id.uuidString.lowercased())" }
    }
}

/// What the pre-flight is preparing.
enum RideKind: Hashable {
    case ftpTest, freeERG, resistance
    case workout(WorkoutRef)
    var id: RideKindID {
        switch self { case .ftpTest: .ftpTest; case .freeERG: .freeERG; case .resistance: .resistance; case .workout: .workout }
    }
}

/// Sections of Home that can be scrolled to.
enum HomeSection: String, Hashable {
    case today, ftp, quickRides, library, upcoming, mine
}
