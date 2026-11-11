// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "macOSFocusGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "opera-guard", targets: ["OperaGuard"]),
        .executable(name: "focus-guard", targets: ["FocusGuard"]),
        .executable(name: "opera-guard-integration-tests", targets: ["OperaGuardIntegrationTests"]),
    ],
    targets: [
        .target(name: "GuardCore"),
        .target(name: "OperaGuardKit", dependencies: ["GuardCore"]),
        .target(name: "FocusGuardKit", dependencies: ["GuardCore"]),
        .executableTarget(name: "OperaGuard", dependencies: ["OperaGuardKit"]),
        .executableTarget(name: "FocusGuard", dependencies: ["FocusGuardKit"]),
        .executableTarget(
            name: "OperaGuardIntegrationTests",
            dependencies: ["OperaGuardKit"],
            path: "IntegrationTests/OperaGuard"
        ),
        .testTarget(name: "OperaGuardTests", dependencies: ["OperaGuardKit"]),
        .testTarget(name: "FocusGuardTests", dependencies: ["FocusGuardKit"]),
    ]
)
