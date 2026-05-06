// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BuildRunProbe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "BuildRunProbe", targets: ["BuildRunProbe"]),
    ],
    targets: [
        .executableTarget(name: "BuildRunProbe"),
    ]
)
