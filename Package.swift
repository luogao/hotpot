// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Manatee",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Manatee",
            path: "Sources/Manatee",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedLibrary("sqlite3"),
            ]),
        .testTarget(
            name: "ManateeTests",
            dependencies: ["Manatee"]
        )
    ]
)
