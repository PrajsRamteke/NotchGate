// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchGate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchGate", targets: ["NotchGate"]),
        .executable(name: "notchgate-hook", targets: ["NotchGateHook"]),
        .library(name: "NotchGateKit", targets: ["NotchGateKit"]),
    ],
    targets: [
        // Shared wire protocol + socket transport used by both the app and the hook.
        .target(name: "NotchGateKit"),

        // Tiny CLI that Claude Code invokes as a command hook.
        .executableTarget(
            name: "NotchGateHook",
            dependencies: ["NotchGateKit"]
        ),

        // The menu-bar app that renders the notch island.
        .executableTarget(
            name: "NotchGate",
            dependencies: ["NotchGateKit"]
        ),

        .testTarget(name: "NotchGateKitTests", dependencies: ["NotchGateKit"]),
        .testTarget(name: "NotchGateTests", dependencies: ["NotchGate", "NotchGateKit"]),
    ]
)
