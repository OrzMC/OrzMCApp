// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OrzMCAppKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OrzMCFoundation",
            targets: ["OrzMCFoundation"]
        ),
        .library(
            name: "OrzMCLauncher",
            targets: ["OrzMCLauncher"]
        ),
        .library(
            name: "OrzMCProtocol",
            targets: ["OrzMCProtocol"]
        ),
        .library(
            name: "OrzMCRemoteHosting",
            targets: ["OrzMCRemoteHosting"]
        ),
        .library(
            name: "OrzMCDesignSystem",
            targets: ["OrzMCDesignSystem"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Kitura/BlueSocket.git", from: "2.0.4")
    ],
    targets: [
        .target(
            name: "OrzMCFoundation",
            path: "Sources/OrzMCFoundation"
        ),
        .target(
            name: "OrzMCLauncher",
            dependencies: ["OrzMCFoundation"],
            path: "Sources/OrzMCLauncher"
        ),
        .target(
            name: "OrzMCProtocol",
            dependencies: [
                .product(name: "Socket", package: "BlueSocket")
            ],
            path: "OrzMC/MobileHelper(iOS)/Protocol"
        ),
        .target(
            name: "OrzMCRemoteHosting",
            dependencies: ["OrzMCFoundation"],
            path: "Sources/OrzMCRemoteHosting"
        ),
        .target(
            name: "OrzMCDesignSystem",
            path: "Sources/OrzMCDesignSystem"
        ),
        .testTarget(
            name: "OrzMCProtocolTests",
            dependencies: ["OrzMCProtocol"],
            path: "Tests/OrzMCProtocolTests"
        ),
        .testTarget(
            name: "OrzMCLauncherTests",
            dependencies: ["OrzMCLauncher"],
            path: "Tests/OrzMCLauncherTests"
        ),
        .testTarget(
            name: "OrzMCRemoteHostingTests",
            dependencies: ["OrzMCRemoteHosting"],
            path: "Tests/OrzMCRemoteHostingTests"
        ),
        .testTarget(
            name: "OrzMCDesignSystemTests",
            dependencies: ["OrzMCDesignSystem"],
            path: "Tests/OrzMCDesignSystemTests"
        )
    ]
)
