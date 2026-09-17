// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Teslaris",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Foundation-only formatting the app depends on. Kept free of AppKit
        // so it builds and tests on any platform, not just a Mac.
        .target(
            name: "TeslarisShared",
            path: "Sources/TeslarisShared"
        ),
        .executableTarget(
            name: "Teslaris",
            dependencies: ["TeslarisShared"],
            path: "Sources/Teslaris"
        ),
        .testTarget(
            name: "TeslarisTests",
            dependencies: ["Teslaris", "TeslarisShared"],
            path: "Tests/TeslarisTests"
        ),
        // Depends on the shared target alone, so the formatting rules can be
        // checked without compiling anything that needs AppKit.
        .testTarget(
            name: "TeslarisSharedTests",
            dependencies: ["TeslarisShared"],
            path: "Tests/TeslarisSharedTests"
        )
    ]
)
