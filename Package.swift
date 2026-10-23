// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FTPunk",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .executable(name: "FTPunkPreview", targets: ["FTPunkApp"]),
        .library(name: "FTPunkDomain", targets: ["FTPunkDomain"]),
        .library(name: "FTPunkDevices", targets: ["FTPunkDevices"]),
        .library(name: "FTPunkStorage", targets: ["FTPunkStorage"]),
        .library(name: "FTPunkIntegrations", targets: ["FTPunkIntegrations"])
    ],
    targets: [
        .target(name: "FTPunkDomain"),
        .target(name: "FTPunkDevices", dependencies: ["FTPunkDomain"]),
        .target(name: "FTPunkStorage", dependencies: ["FTPunkDomain"]),
        .target(name: "FTPunkIntegrations", dependencies: ["FTPunkDomain", "FTPunkStorage"]),
        .executableTarget(name: "FTPunkApp", dependencies: ["FTPunkDomain", "FTPunkDevices", "FTPunkStorage", "FTPunkIntegrations"],
                          path: "App", exclude: ["Info.plist", "Assets.xcassets"]),
        .testTarget(name: "FTPunkTests", dependencies: ["FTPunkDomain", "FTPunkDevices", "FTPunkStorage", "FTPunkIntegrations"])
    ]
)
