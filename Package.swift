// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Teslaris",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // In-app updates. Sparkle only installs a build whose Developer ID
        // signature matches the running one, so this is only possible now
        // that releases are signed.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
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
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "TeslarisShared"
            ],
            path: "Sources/Teslaris"
        ),
        // The widget is a second executable, hand-assembled into an .appex
        // the same way the .app itself is assembled — no Xcode project.
        //
        // -e _NSExtensionMain is what makes the binary loadable as an
        // extension: @main on the WidgetBundle still generates the SwiftUI
        // entry point, but the system starts an appex through
        // NSExtensionMain rather than main(). Xcode's widget template sets
        // exactly this flag. unsafeFlags is fine here and only here —
        // SwiftPM forbids it in a package consumed as a dependency, and
        // Teslaris is only ever the root.
        .executableTarget(
            name: "TeslarisWidget",
            dependencies: ["TeslarisShared"],
            path: "Sources/TeslarisWidget",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
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
