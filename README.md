<p align="center">
  <a href="https://github.com/tachyonics/swift-local-containers/actions/workflows/swift.yml">
    <img src="https://github.com/tachyonics/swift-local-containers/actions/workflows/swift.yml/badge.svg" alt="Build">
  </a>
  <a href="https://swiftpackageindex.com/tachyonics/swift-local-containers">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftachyonics%2Fswift-local-containers%2Fbadge%3Ftype%3Dswift-versions" alt="Swift versions">
  </a>
  <a href="https://codecov.io/gh/tachyonics/swift-local-containers">
    <img src="https://codecov.io/gh/tachyonics/swift-local-containers/graph/badge.svg" alt="Code coverage">
  </a>
  <a href="https://swiftpackageindex.com/tachyonics/swift-local-containers">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftachyonics%2Fswift-local-containers%2Fbadge%3Ftype%3Dplatforms" alt="Platforms">
  </a>
  <a href="https://www.apache.org/licenses/LICENSE-2.0">
    <img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="License: Apache 2.0">
  </a>
</p>

# Swift Local Containers

> [!WARNING]
> This package is under active development. APIs are subject to change without notice.

A Swift package for managing local containers in tests — define containers as types, start them automatically with Swift Testing, and tear them down when your suite completes.

## Proposed Features

- **Type-safe container definitions** via the `ContainerKey` protocol
- **Swift Testing integration** with `@Suite(.containers(...))` traits
- **Cross-platform runtime auto-selection** — Docker/Podman on Linux, Apple Containerization on macOS 26+
- **Built-in LocalStack support** with CDK and CloudFormation setup steps
- **Flexible wait strategies** — port readiness, health check, log matching, fixed delay, or custom logic
- **Shared containers across test suites** with `@Suite(.sharedContainers(...))` for performance

## Proposed Usage

### Define a container

Conform to `ContainerKey` to declare a reusable container definition:

```swift
import LocalContainers

struct MyPostgres: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(
            image: "postgres:16",
            ports: [PortMapping(containerPort: 5432)],
            environment: ["POSTGRES_PASSWORD": "test"],
            healthCheck: HealthCheckConfig(
                test: ["CMD", "pg_isready"],
                interval: .seconds(10),
                timeout: .seconds(5),
                retries: 3
            ),
            waitStrategy: .healthCheck
        )
    )
}
```

### Use in tests

Attach containers to a test suite with the `.containers(...)` trait. Access running containers through `ContainerTestContext`:

```swift
import Testing
import ContainerTestSupport

@Suite(.containers(MyPostgres.self))
struct DatabaseTests {
    @Test func connectionWorks() async throws {
        let ctx = try #require(ContainerTestContext.current)
        let postgres = try ctx[MyPostgres.self]
        let hostPort = try postgres.mappedPort(5432)

        // Connect to localhost:\(hostPort) ...
    }
}
```

### LocalStack with CDK

Use the built-in `LocalStackContainer` builder and compose setup steps:

```swift
import LocalContainers
import LocalStack

struct MyLocalStack: ContainerKey {
    static let spec = ContainerSpec(
        LocalStackContainer(
            services: ["s3", "dynamodb", "sqs"]
        ).configuration(),
        setups: [
            CDKSetup(appPath: "infra/app.ts", stackName: "MyStack")
        ]
    )
}
```

## Requirements

- Swift 6.1+
- macOS 15+ or Linux
- Docker, Podman, or Apple Containerization (macOS 26+)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tachyonics/swift-local-containers.git", from: "0.1.0")
]
```

Then add the libraries you need to your test target:

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: [
        .product(name: "LocalContainers", package: "swift-local-containers"),
        .product(name: "ContainerTestSupport", package: "swift-local-containers"),
        // Optional:
        // .product(name: "LocalStack", package: "swift-local-containers"),
        // .product(name: "DockerRuntime", package: "swift-local-containers"),
        // .product(name: "PlatformRuntime", package: "swift-local-containers"),
    ]
)
```

## License

This project is licensed under the Apache License, Version 2.0.
