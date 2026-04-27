# TODO

## ContainerizationRuntime

- [x] Implement `pullImage()` using `Containerization.Image` to pull OCI images
- [x] Implement `startContainer()` to create and start a VM with the container image
- [x] Implement `stopContainer()` to stop the VM
- [x] Implement `removeContainer()` to remove the VM and clean up resources
- [x] Implement `ContainerizationManager` actor for VM/image lifecycle
- [x] Add unit tests for ContainerizationRuntime (22 tests covering `LogAccumulatingWriter`, `qualifyImageReference`, `resolvePortMappings`, and absent-container behaviour in `ContainerizationManagerTests`). Running in CI.
- [x] Add ContainerizationRuntime integration test (macOS 26+) — 3 tests covering full lifecycle, unknown-container error, and port mapping. Gated on `containerizationAvailable` which probes kernel presence and vmnet availability. Tests skip under `swift test` because `com.apple.vm.networking` is a restricted entitlement that requires a trusted signing identity — ad-hoc codesigning is silently ignored on SIP-enabled macOS. Runnable via Xcode (which signs with a development certificate). Waiting on Apple to provide a CLI-compatible entitlement path before these can run in CI.

## Wait Strategies

- [x] Implement wait strategy polling in `ContainerTrait` before handing control to tests
- [x] Implement port connectivity check (`.port`)
- [x] Implement health check polling via inspect loop (`.healthCheck`)
- [x] Implement log output monitoring (`.logMessage`)
- [x] Implement fixed delay (`.fixedDelay`)
- [x] Implement custom closure wait (`.custom`)
- [x] Add timeout handling for wait strategies

## LocalStack Setup Steps

- [x] Implement `CloudFormationSetup.createStack()` — POST to CloudFormation API with `Action=CreateStack`
- [x] Implement `CloudFormationSetup.waitForStack()` — poll `DescribeStacks` until `CREATE_COMPLETE`
- [x] Implement `CloudFormationSetup.deleteStack()` — POST with `Action=DeleteStack`
- [x] Add functional tests for CloudFormation setup steps (covered end-to-end by `CloudFormationIntegrationTests`, `CDKIntegrationTests`, and `CDKSetupImperativeTests` against a real LocalStack container)

## Next Milestones

### 1. Finish CDK support

- [x] Implement `CDKSetup.runShell()` using `Foundation.Process` to run `cdk bootstrap`, `cdk synth`, etc.
- [x] Add functional tests for CDK setup steps
- [x] Make the deployment path transparently stub `/cdk-bootstrap/hnb659fds/version` in LocalStack (via the SSM `PutParameter` API) before `CreateStack`, using a bootstrap version value (`"20"`) that satisfies CDK's `CheckBootstrapVersion` rule. Extracted into `BootstrapVersionStub` and triggered automatically from `CloudFormationSetup` whenever the template body references the CDK bootstrap marker. User CDK apps require **zero** modification to be usable in tests AND production — the same stack definition (with `DefaultStackSynthesizer`) deploys cleanly to LocalStack for tests and to real CloudFormation for prod.
- [x] The `@LocalStackContainer` macro handles CDK-sourced `StackOutputs` structs uniformly — once `cdkapps[]` synthesizes a template at build time, the runtime deployment path is indistinguishable from a handwritten CF template. No separate `@CDKContainer` macro needed.
- [x] Opt-in escape hatch for CDK stacks that use assets. `CDKSetup(autoBootstrap: true)` now delegates to `cdklocal` for both bootstrap and deploy — the full CDK flow, with real asset upload to a LocalStack-hosted `CDKToolkit` stack. Scope is intentionally limited to the imperative path: the declarative `cdkapps[]` build plugin still only handles assetless stacks, because the primary use case for this framework is web-app dependency stacks (DDB/SQS/SNS/Step Functions) rather than the web app's own runtime infrastructure. Users with assets opt in by setting `autoBootstrap: true` and adding `aws-cdk-local` to their CDK app's `devDependencies`; everyone else sees no behavior change and no dependency cost.

### 2. Configurable codegen

- [x] Replace the "scan any .json for `AWSTemplateFormatVersion`" behaviour in `ContainerCodeGenPlugin` with an explicit `.local-containers/codegen.json` manifest listing template sources and generated struct names. Target scoping is implicit (plugin resolves each entry's `source` against every target's source directory and acts on matches).
- [x] Support CDK-synthesized templates as an input to codegen. Plugin handles `cdkapps[]` entries: invokes `ContainerCodeGenTool cdk-synth` which runs `npx cdk synth` at build time under the sandbox, stages the resulting template alongside the generated struct, and flows through the same codegen pipeline as handwritten templates. Build-time synth requires `node_modules/.bin/cdk` to exist in the CDK app directory — seeded once via the `bootstrap` command plugin.
- [x] Add `bootstrap` command plugin for one-time setup (currently: `npm install` for `cdkapps[]` entries). Lives outside the build sandbox with explicit `.allowNetworkConnections` + `.writeToPackageDirectory` permissions. Designed generically so future categories (docker image pre-pulls, Python virtualenvs, etc.) can be added as additional handler blocks without introducing new commands.

### 3. Real-container LocalStack tests

- [x] Add Docker integration test that exercises setup steps (`CloudFormationIntegrationTests` deploys a real stack against a LocalStack container via `DockerContainerRuntime`).
- [x] Replace mock-based LocalStack integration test with a real container test (the original `LocalStackIntegrationTests` was never actually mock-based — it tests endpoint derivation on a hand-built `RunningContainer`. Real-container CDK + CloudFormation coverage now lives in `CDKIntegrationTests`, `CDKSetupImperativeTests`, and `CloudFormationIntegrationTests`).

### 4. Dockerfile-based service integration (design + build)

- [ ] Design a primitive for building an image from a Dockerfile and running it as a service container (e.g. `BuildImageSetup` / `ServiceContainer`), exposing ports and wait strategies.
- [ ] Design the debug-attach story for Swift services: remote LLDB from macOS into the Linux container over a forwarded port, targeting a Swift webapp/service defined in the same workspace as the tests. Non-Swift runtimes are explicitly out of scope.
- [ ] Implement once design is agreed.

### 5. Real-AWS deployment alternative

- [ ] Add a `ContainerSetup` alternative that runs CDK deploy against a real AWS account and returns the same `StackOutputs` shape — opt-in via env var so it stays off by default in CI.
- [ ] Document credential + cost tradeoffs.

## Watching & deferred decisions

Items tracked for future reference but not currently scheduled. Each depends on external events (upstream releases, real user demand) or represents a deferred design decision.

- [ ] **Investigate: support local-path Swift package dependencies in Dockerfile-based service container builds.** `@DockerfileContainer` tarballs the `context:` directory and ships it to the daemon, which then runs `swift build` inside the container. If the user's `Package.swift` has a `package(path: "...")` dependency pointing outside the build context (common in monorepos, or when consuming swift-local-containers itself via a local path during development), SwiftPM's resolution fails inside the container — the path isn't reachable. This first surfaced when wiring task-cluster's integration test as a local path dep against swift-local-containers; fix was to publish swift-local-containers as a proper version tag and consume it as a normal git dep, which sidesteps the issue. Workarounds for users with genuine path-dep needs today: gate the dep + integration test target on an env var in `Package.swift` (loses ergonomics, well-established pattern from grpc-swift et al.), or move the integration test into a separate sibling Swift package. Future investigation: detect path deps from `Package.swift` and stage them automatically into a sub-directory of the tar context, then rewrite the path to be relative to the tar root before sending to the daemon. Or document the env-var-gating pattern as the supported workaround. Not currently scheduled — the workarounds are fine for the use cases we've seen.

- [ ] **Monitor the `aws-cdk-local` migration path.** The `autoBootstrap: true` CDK path relies on `aws-cdk-local` monkey-patching `aws-cdk` internals (`lib/cdk-toolkit`, `lib/serialize`, `lib/api`, etc.) that were removed in `aws-cdk 2.1114.0`. The fixture's `package.json` therefore pins `aws-cdk` to `2.1113.0`; see the `_comment_aws_cdk_pin` field in that file and the callout in the README. Upstream tracking issue: [localstack/aws-cdk-local#126](https://github.com/localstack/aws-cdk-local/issues/126). The aws-cdk team has published an official replacement, [`@aws-cdk/toolkit-lib`](https://docs.aws.amazon.com/cdk/api/toolkit-lib/), that `cdklocal` is expected to migrate to. When that lands: unpin `aws-cdk`, bump `aws-cdk-local`, rerun the integration tests, drop the README callout, revisit the `_comment_aws_cdk_pin` field. If `cdklocal` stalls for more than ~6 months or ships abandoned, consider writing a small Swift-Process-driven wrapper around `@aws-cdk/toolkit-lib` directly and deprecating the `cdklocal` dependency.

- [x] **Volume mount support in `ContainerConfiguration`.** Already implemented: `VolumeMount` struct with `hostPath`, `containerPath`, `readOnly`. Plumbed through `DockerContainerRuntime` (via `HostConfig.Binds`) and `ContainerizationRuntime` (via `config.mounts.append(.share(...))`). Unit-tested in both `DockerContainerRuntimeTests` and `ContainerConfigurationTests`.

- [x] **Use volume mounts to enable LocalStack Lambda in integration tests.** Added `volumes` parameter to `LocalStackContainer`, added `dockerSocketAvailable` gate in `TestHelpers.swift`, added `LambdaStack` fixture in `app.js`, and added `deployLambdaCDKApp` test in `CDKSetupImperativeTests` that mounts `/var/run/docker.sock` and deploys a real Lambda end-to-end via cdklocal. Test is gated on Docker socket availability so it skips gracefully in environments without a standard socket path.

- [ ] **Revisit "Option B" — declarative `cdkapps[]` for asset-bearing stacks.** The current declarative path synthesizes CDK templates at build time and stages them for the `@LocalStackContainer` macro. That's clean for assetless stacks but not for asset-bearing ones, because assets need to be staged at deploy time with LocalStack already running — something the build plugin can't coordinate. Users with asset-bearing stacks currently have to drop down to imperative `CDKSetup(autoBootstrap: true)` and lose the typed `StackOutputs` generation.

  **Only worth doing if real user demand materializes.** The primary use case for this framework (web-app dependency stacks — DynamoDB / SQS / SNS / Step Functions) is assetless, so this gap is likely to stay a minority concern. If it becomes a priority: design a manifest section like `cdkappsWithAssets[]` plus a runtime setup type (`CDKLocalDeploySetup`) that invokes `cdklocal` at test time against an app directory path baked into the generated struct. Nontrivial — needs a dedicated design pass that addresses (a) how to statically extract output keys at build time without running `cdklocal synth` under the SwiftPM build sandbox (which can't reach the network), (b) how to plumb the app directory path from build time to test time in a machine-portable way, and (c) how the generated struct's `templatePath`-like mechanism works when the template is constructed at test time rather than build time.

## Integration Tests

- [x] Add Docker integration test that exercises wait strategies
