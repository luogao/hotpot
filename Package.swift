// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhoCooking",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WhoCooking",
            path: "Sources/WhoCooking",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
