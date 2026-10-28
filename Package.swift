// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyAwake",
    targets: [
        .target(
            name: "KeyAwakeCore",
            path: "Sources",
            exclude: ["App", "Agent"]
        ),
        .testTarget(
            name: "KeyAwakePolicyTests",
            dependencies: ["KeyAwakeCore"],
            path: "Tests/PolicyTests"
        ),
        .testTarget(
            name: "KeyAwakeSettingsTests",
            dependencies: ["KeyAwakeCore"],
            path: "Tests/SettingsTests"
        ),
    ]
)
