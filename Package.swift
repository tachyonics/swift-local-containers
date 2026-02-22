// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-local-containers",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LocalContainers", targets: ["LocalContainers"]),
        .library(name: "DockerRuntime", targets: ["DockerRuntime"]),
        .library(name: "ContainerizationRuntime", targets: ["ContainerizationRuntime"]),
        .library(name: "PlatformRuntime", targets: ["PlatformRuntime"]),
        .library(name: "LocalStack", targets: ["LocalStack"]),
        .library(name: "ContainerTestSupport", targets: ["ContainerTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/containerization.git", branch: "main"),
    ],
    targets: [
        // MARK: - Core

        .target(
            name: "LocalContainers",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        // MARK: - Platform Backends

        .target(
            name: "DockerRuntime",
            dependencies: [
                "LocalContainers",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        .target(
            name: "ContainerizationRuntime",
            dependencies: [
                "LocalContainers",
                .product(name: "Containerization", package: "containerization"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // MARK: - Platform Auto-Selection

        .target(
            name: "PlatformRuntime",
            dependencies: [
                "LocalContainers",
                "DockerRuntime",
                "ContainerizationRuntime",
            ]
        ),

        // MARK: - LocalStack

        .target(
            name: "LocalStack",
            dependencies: [
                "LocalContainers",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // MARK: - Test Support

        .target(
            name: "ContainerTestSupport",
            dependencies: [
                "LocalContainers",
                "PlatformRuntime",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "LocalContainersTests",
            dependencies: ["LocalContainers"]
        ),

        .testTarget(
            name: "DockerRuntimeTests",
            dependencies: ["DockerRuntime"]
        ),

        .testTarget(
            name: "LocalStackTests",
            dependencies: ["LocalStack"]
        ),

        .testTarget(
            name: "ContainerTestSupportTests",
            dependencies: [
                "ContainerTestSupport",
                "LocalContainers",
            ]
        ),

        .testTarget(
            name: "PlatformRuntimeTests",
            dependencies: [
                "PlatformRuntime",
                "LocalContainers",
            ]
        ),

        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "ContainerTestSupport",
                "LocalStack",
                "DockerRuntime",
                "PlatformRuntime",
            ]
        ),
    ]
)
