// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "token-torch-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenTorchCore", targets: ["TokenTorchCore"]),
        .executable(name: "token-torch-cli", targets: ["token-torch-cli"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "TokenTorchCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "token-torch-cli",
            dependencies: [
                "TokenTorchCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "TokenTorchCoreTests",
            dependencies: ["TokenTorchCore"]
        )
    ]
)
