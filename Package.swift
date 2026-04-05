// swift-tools-version: 6.1

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-local-containers",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LocalContainers", targets: ["LocalContainers"]),
        .library(name: "DockerRuntime", targets: ["DockerRuntime"]),
        .library(name: "PlatformRuntime", targets: ["PlatformRuntime"]),
        .library(name: "LocalStack", targets: ["LocalStack"]),
        .library(name: "ContainerTestSupport", targets: ["ContainerTestSupport"]),
        .library(name: "ContainerMacrosLib", targets: ["ContainerMacrosLib"]),
        .plugin(name: "ContainerCodeGen", targets: ["ContainerCodeGen"]),
    ],
    traits: [
        .trait(
            name: "Containerization",
            description: "Enable experimental Apple Containerization backend (macOS only)"
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/tachyonics/smockable.git", from: "1.0.0-alpha.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // MARK: - Build Plugins

        .plugin(
            name: "ContainerCodeGen",
            capability: .buildTool(),
            dependencies: ["ContainerCodeGenTool"]
        ),

        .executableTarget(name: "ContainerCodeGenTool"),

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
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),

        // MARK: - Platform Auto-Selection

        .target(
            name: "PlatformRuntime",
            dependencies: [
                "LocalContainers",
                "DockerRuntime",
            ]
        ),

        // MARK: - LocalStack

        .target(
            name: "LocalStack",
            dependencies: [
                "LocalContainers",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
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

        // MARK: - Macros

        .target(
            name: "ContainerMacrosLib",
            dependencies: [
                "ContainerMacros",
                "LocalContainers",
                "ContainerTestSupport",
                "LocalStack",
                "PlatformRuntime",
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "LocalContainersTests",
            dependencies: [
                "LocalContainers",
                .product(name: "Smockable", package: "smockable"),
            ]
        ),

        .testTarget(
            name: "DockerRuntimeTests",
            dependencies: [
                "DockerRuntime",
                .product(name: "Smockable", package: "smockable"),
            ]
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
                .product(name: "Smockable", package: "smockable"),
            ]
        ),

        .testTarget(
            name: "PlatformRuntimeTests",
            dependencies: [
                "PlatformRuntime",
                "ContainerTestSupport",
                "LocalContainers",
            ]
        ),

        .testTarget(
            name: "ContainerCodeGenToolTests",
            dependencies: []
        ),

        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "ContainerTestSupport",
                "ContainerMacrosLib",
                "LocalStack",
                "DockerRuntime",
                "PlatformRuntime",
            ],
            plugins: [.plugin(name: "ContainerCodeGen")]
        ),

        .testTarget(
            name: "ContainerMacrosTests",
            dependencies: [
                "ContainerMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)

// MARK: - Macro target (appended separately for type inference)

package.targets.append(
    .macro(
        name: "ContainerMacros",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        ]
    )
)

// MARK: - macOS-only: Apple Containerization backend

#if os(macOS)
package.dependencies.append(
    .package(url: "https://github.com/apple/containerization.git", from: "0.28.0")
)

package.products.append(
    .library(name: "ContainerizationRuntime", targets: ["ContainerizationRuntime"])
)

package.targets.append(
    .target(
        name: "ContainerizationRuntime",
        dependencies: [
            "LocalContainers",
            .product(name: "Containerization", package: "containerization"),
            .product(name: "ContainerizationExtras", package: "containerization"),
            .product(name: "Logging", package: "swift-log"),
        ]
    )
)

// Add ContainerizationRuntime as a dependency of PlatformRuntime on macOS
if let platformIdx = package.targets.firstIndex(where: { $0.name == "PlatformRuntime" }) {
    package.targets[platformIdx].dependencies.append(
        .targetItem(
            name: "ContainerizationRuntime",
            condition: .when(traits: ["Containerization"])
        )
    )
}
#endif
