// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "token-torch-swift",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "TokenTorchCore", targets: ["TokenTorchCore"]),
        .executable(name: "token-torch-cli", targets: ["TokenTorchCli"])
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
            name: "TokenTorchCli",
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
