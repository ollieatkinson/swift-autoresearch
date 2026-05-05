// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-autoresearch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "autoresearch", targets: ["AutoresearchCLI"]),
        .library(name: "Autoresearch", targets: ["AutoresearchCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.3"),
    ],
    targets: [
        .target(
            name: "AutoresearchCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Autoresearch"
        ),
        .executableTarget(
            name: "AutoresearchCLI",
            dependencies: [
                "AutoresearchCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/autoresearch-cli"
        ),
        .testTarget(
            name: "AutoresearchTests",
            dependencies: ["AutoresearchCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
