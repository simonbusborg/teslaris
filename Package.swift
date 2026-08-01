// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Teslaris",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Teslaris",
            path: "Sources/Teslaris"
        ),
        .testTarget(
            name: "TeslarisTests",
            dependencies: ["Teslaris"],
            path: "Tests/TeslarisTests"
        )
    ]
)
