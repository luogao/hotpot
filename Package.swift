// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HotPot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HotPot",
            path: "Sources/HotPot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
