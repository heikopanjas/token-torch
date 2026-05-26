// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "burn-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BurnCore", targets: ["BurnCore"]),
        .executable(name: "burn-cli", targets: ["burn-cli"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "BurnCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "burn-cli",
            dependencies: [
                "BurnCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "BurnCoreTests",
            dependencies: ["BurnCore"]
        )
    ]
)
