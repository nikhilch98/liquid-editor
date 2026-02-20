// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrackingTester",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TrackingTester",
            dependencies: [],
            path: "Sources"
        )
    ]
)
