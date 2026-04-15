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

### LocalStack with CDK — imperative form

Use the built-in `LocalStackContainer` builder and compose setup steps manually. `CDKSetup` runs CDK at test time and deploys to LocalStack. Two operating modes depending on whether your stack uses CDK assets.

**`autoBootstrap: false` (default) — assetless stacks, fast path.** Runs `cdk synth` locally and hands the template to `CloudFormationSetup`, which transparently stubs the `/cdk-bootstrap/hnb659fds/version` SSM parameter before `CreateStack`. Use this for any stack containing only "inline" resources — DynamoDB tables, SQS queues, SNS topics, Step Functions, S3 buckets, IAM roles, etc. No real bootstrap needed.

```swift
import LocalContainers
import LocalStack

struct MyLocalStack: ContainerKey {
    static let spec = ContainerSpec(
        LocalStackContainer(
            services: ["s3", "dynamodb", "sqs"]
        ).configuration(),
        setups: [
            CDKSetup(
                cdkAppPath: "infra",
                stackName: "MyStack"
            )
        ]
    )
}
```

**`autoBootstrap: true` — asset-bearing stacks.** Delegates to [`aws-cdk-local`](https://www.npmjs.com/package/aws-cdk-local) (the `cdklocal` CLI), which wraps the regular CDK CLI and routes every AWS API call at LocalStack. Runs `cdklocal bootstrap` to create a real `CDKToolkit` stack inside LocalStack, then `cdklocal deploy` to upload assets and create the application stack. Use this when your stack uses `lambda.Code.fromAsset(...)`, `ecs.ContainerImage.fromAsset(...)`, bundled CloudFormation init scripts, or any other asset type.

```swift
struct MyStackWithLambda: ContainerKey {
    static let spec = ContainerSpec(
        LocalStackContainer().configuration(),  // default services
        setups: [
            CDKSetup(
                cdkAppPath: "infra",
                stackName: "MyStack",
                autoBootstrap: true
            )
        ]
    )
}
```

Requires `aws-cdk-local` in your CDK app's `devDependencies`. Adds ~30 seconds per test suite for the `cdklocal bootstrap` step.

> [!IMPORTANT]
> **`aws-cdk` must be pinned to `2.1113.0` or earlier in your CDK app's `package.json`** until `aws-cdk-local` ships a fix for [localstack/aws-cdk-local#126](https://github.com/localstack/aws-cdk-local/issues/126).
>
> Versions of `aws-cdk` from `2.1114.0` onward removed the internal module exports (`lib/cdk-toolkit`, `lib/serialize`, `lib/api`, etc.) that `cdklocal` monkey-patches to route CDK calls at LocalStack. With an unpinned `aws-cdk`, `cdklocal bootstrap` fails immediately with `ERR_PACKAGE_PATH_NOT_EXPORTED`. The aws-cdk team has introduced an official replacement, [`@aws-cdk/toolkit-lib`](https://docs.aws.amazon.com/cdk/api/toolkit-lib/), and `cdklocal` is in the process of migrating — once it does, this pin can be removed.
>
> This constraint only applies to the `autoBootstrap: true` path. Projects using `autoBootstrap: false` (the default — SSM-stub fast path) or using the declarative `cdkapps[]` flow for assetless stacks are **not** affected and can freely consume any `aws-cdk` version.
>
> Example `package.json` snippet:
>
> ```json
> {
>   "devDependencies": {
>     "aws-cdk": "2.1113.0",
>     "aws-cdk-local": "^2.19.0"
>   }
> }
> ```

### LocalStack with CDK — declarative form (recommended)

For projects that want strongly-typed access to stack outputs and have the CDK synth happen at build time (rather than test time), declare your CloudFormation templates and CDK apps in `.local-containers/codegen.json` at the package root:

```json
{
  "templates": [
    {
      "source": "Resources/my-infra.json",
      "structName": "MyInfraOutputs"
    }
  ],
  "cdkapps": [
    {
      "source": "Resources/my-cdk-app",
      "stackName": "MyStack",
      "structName": "MyStackOutputs"
    }
  ]
}
```

The `ContainerCodeGen` build plugin reads the manifest, runs `cdk synth` for each `cdkapps[]` entry during `swift build`, and generates a `StackOutputs`-conforming struct with typed accessors for every output declared in the template's `Outputs` section. Use the generated struct in your test suite via `@Containers` + `@LocalStackContainer`:

```swift
import ContainerMacrosLib
import ContainerTestSupport
import Testing

@Containers
struct MyContainers {
    @LocalStackContainer(stackName: "my-stack")
    var infra: MyStackOutputs
}

@Suite(MyContainers.containerTrait, .tags(.integration))
struct InfraTests {
    let containers = MyContainers()

    @Test func deployedStackIsUsable() async throws {
        let infra = containers.infra
        // infra.bucketName, infra.queueUrl, ... are strongly typed
        // from the template's Outputs section
        print(infra.awsEndpoint, infra.bucketName)
    }
}
```

#### Bootstrapping the declarative CDK flow

SwiftPM's build-plugin sandbox denies network access, so the build plugin cannot run `npm install` itself. Run the `bootstrap` command plugin once after a fresh checkout (or whenever you add a new `cdkapps[]` entry):

```sh
swift package --allow-network-connections all \
              --allow-writing-to-package-directory bootstrap
```

This iterates every `cdkapps[]` entry in the manifest and runs `npm install` in each CDK app directory. After it completes, `swift build` and `swift test` work normally with the sandbox fully intact.

#### Continuous integration

Your CI pipeline needs two things:

1. **Node.js** available on PATH (GitHub-hosted `ubuntu-*` and `macos-*` runners include it by default).
2. A `swift package bootstrap` step **before** any `swift build`/`swift test` command. Without it, the build will fail when the CDK codegen plugin cannot find `node_modules/.bin/cdk`.

Example GitHub Actions snippet:

```yaml
- uses: actions/checkout@v6
- name: Bootstrap
  run: swift package --allow-network-connections all --allow-writing-to-package-directory bootstrap
- name: Run tests
  run: swift test
```

This requirement only applies to projects that declare `cdkapps[]` entries. Projects using `templates[]` for handwritten CloudFormation — or no manifest at all — need no bootstrap step.

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
