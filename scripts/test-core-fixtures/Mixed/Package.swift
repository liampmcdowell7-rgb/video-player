// swift-tools-version:5.9
// Fixture for scripts/test-core-tests.sh only (#28 item 1). Never part of the app or of VideoPlayerCore.
import PackageDescription

let package = Package(
    name: "MixedFixture",
    targets: [
        .target(name: "MixedFixture"),
        .testTarget(name: "MixedFixtureTests", dependencies: ["MixedFixture"]),
    ]
)
