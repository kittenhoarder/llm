// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "llm",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .executable(
            name: "foundation-chat",
            targets: ["FoundationChat"]
        ),
        .executable(
            name: "SerpAPITest",
            targets: ["SerpAPITest"]
        ),
        .library(
            name: "FoundationChatCore",
            targets: ["FoundationChatCore"]
        ),
        .library(
            name: "FoundationChatMac",
            targets: ["FoundationChatMac"]
        ),
        .library(
            name: "FoundationChatiOS",
            targets: ["FoundationChatiOS"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.6.2"
        ),
        .package(
            url: "https://github.com/stephencelis/SQLite.swift.git",
            from: "0.15.3"
        ),
        .package(
            url: "https://github.com/Dripfarm/SVDB.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        // Shared core library
        .target(
            name: "FoundationChatCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "SVDB", package: "SVDB"),
            ],
            path: "Sources/FoundationChatCore"
        ),
        // CLI executable (uses core)
        .executableTarget(
            name: "FoundationChat",
            dependencies: [
                "FoundationChatCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/FoundationChat"
        ),
        // SerpAPI test executable
        .executableTarget(
            name: "SerpAPITest",
            dependencies: ["FoundationChatCore"],
            path: "Sources/SerpAPITest"
        ),
        // macOS app library
        .target(
            name: "FoundationChatMac",
            dependencies: ["FoundationChatCore"],
            path: "Sources/FoundationChatMac"
        ),
        // iOS app library
        .target(
            name: "FoundationChatiOS",
            dependencies: ["FoundationChatCore"],
            path: "Sources/FoundationChatiOS"
        ),
        // Tests
        .testTarget(
            name: "FoundationChatTests",
            dependencies: ["FoundationChat", "FoundationChatCore"],
            path: "Tests/FoundationChatTests",
            exclude: [
                "Integration/ErrorScenarioTests.swift",
                "Integration/PerformanceTests.swift",
                "Integration/MockLLMService.swift",
                "Services/LLMToolServiceTests.swift",
                "Services/ToolRegistryServiceTests.swift"
            ]
        ),
        .testTarget(
            name: "FoundationChatCoreTests",
            dependencies: ["FoundationChatCore"],
            path: "Tests/FoundationChatCoreTests"
        ),
    ]
)

