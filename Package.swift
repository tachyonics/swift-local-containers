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
        .plugin(name: "ContainerCodeGen", targets: ["ContainerCodeGen"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/tachyonics/smockable.git", from: "1.0.0-alpha.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
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
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        // MARK: - Platform Auto-Selection

        .target(
            name: "PlatformRuntime",
            dependencies: [
                "LocalContainers",
                "DockerRuntime"
            ]
        ),

        // MARK: - LocalStack

        .target(
            name: "LocalStack",
            dependencies: [
                "LocalContainers",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        // MARK: - Test Support

        .target(
            name: "ContainerTestSupport",
            dependencies: [
                "LocalContainers",
                "PlatformRuntime",
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        // MARK: - Build Plugin

        .plugin(
            name: "ContainerCodeGen",
            capability: .buildTool(),
            dependencies: ["ContainerCodeGenTool"]
        ),

        .executableTarget(
            name: "ContainerCodeGenTool"
        ),

        // MARK: - Tests

        .testTarget(
            name: "LocalContainersTests",
            dependencies: [
                "LocalContainers",
                .product(name: "Smockable", package: "smockable")
            ]
        ),

        .testTarget(
            name: "DockerRuntimeTests",
            dependencies: [
                "DockerRuntime",
                .product(name: "Smockable", package: "smockable")
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
                .product(name: "Smockable", package: "smockable")
            ]
        ),

        .testTarget(
            name: "PlatformRuntimeTests",
            dependencies: [
                "PlatformRuntime",
                "LocalContainers",
                .product(name: "Smockable", package: "smockable")
            ]
        ),

        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "ContainerTestSupport",
                "LocalStack",
                "DockerRuntime",
                "PlatformRuntime",
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ],
            exclude: ["Resources"]
        ),

        .testTarget(
            name: "ContainerMacrosTests",
            dependencies: [
                "ContainerMacros",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ]
)

// MARK: - Macros (appended to avoid type inference issues with .macro in array literals)

let macroTarget: Target = .macro(
    name: "ContainerMacros",
    dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
    ]
)
package.targets.append(macroTarget)

package.targets.append(
    .target(
        name: "ContainerMacrosLib",
        dependencies: [
            "ContainerMacros",
            "LocalContainers",
            "ContainerTestSupport",
            "LocalStack"
        ]
    )
)

// MARK: - macOS-only: Apple Containerization backend

#if os(macOS)
let containerizationDep: Package.Dependency = .package(
    url: "https://github.com/apple/containerization.git",
    branch: "main"
)
package.dependencies.append(containerizationDep)

let containerizationProduct: Product = .library(
    name: "ContainerizationRuntime",
    targets: ["ContainerizationRuntime"]
)
package.products.append(containerizationProduct)

let containerizationTarget: Target = .target(
    name: "ContainerizationRuntime",
    dependencies: [
        "LocalContainers",
        .product(name: "Containerization", package: "containerization"),
        .product(name: "Logging", package: "swift-log")
    ]
)
package.targets.append(containerizationTarget)

// Add ContainerizationRuntime as a dependency of PlatformRuntime on macOS
if let platformIdx = package.targets.firstIndex(where: { $0.name == "PlatformRuntime" }) {
    let dep: Target.Dependency = .target(name: "ContainerizationRuntime")
    package.targets[platformIdx].dependencies.append(dep)
}
#endif
