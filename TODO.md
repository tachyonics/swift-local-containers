# TODO

## ContainerizationRuntime

- [x] Implement `pullImage()` using `Containerization.Image` to pull OCI images
- [x] Implement `startContainer()` to create and start a VM with the container image
- [x] Implement `stopContainer()` to stop the VM
- [x] Implement `removeContainer()` to remove the VM and clean up resources
- [x] Implement `ContainerizationManager` actor for VM/image lifecycle
- [ ] Add unit tests for ContainerizationRuntime
- [ ] Add ContainerizationRuntime integration test (macOS 26+)

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
- [ ] Add functional tests for CloudFormation setup steps

## Next Milestones

### 1. Finish CDK support

- [x] Implement `CDKSetup.runShell()` using `Foundation.Process` to run `cdk bootstrap`, `cdk synth`, etc.
- [x] Add functional tests for CDK setup steps
- [x] Make `CDKSetup` transparently stub `/cdk-bootstrap/hnb659fds/version` in LocalStack (via the SSM `PutParameter` API) before `CreateStack`, using a bootstrap version value (`"20"`) that satisfies CDK's `CheckBootstrapVersion` rule. User CDK apps require **zero** modification to be usable in tests AND production — the same stack definition (with `DefaultStackSynthesizer`) deploys cleanly to LocalStack for tests and to real CloudFormation for prod. Fixture in `Tests/IntegrationTests/Resources/cdk-app/app.js` now uses the default synthesizer, matching real production usage.
- [ ] Add an opt-in escape hatch for CDK stacks that use assets (Lambda inline code, Docker image assets, etc.) by invoking `cdklocal bootstrap` when `autoBootstrap: true`. This is the "advanced use case" path: slower (~30s for bootstrap) and introduces an `aws-cdk-local` npm dependency, but it's the only way to handle asset-bearing stacks against LocalStack.
- [ ] Decide whether to support CDK in the `@LocalStackContainer` macro (or add a sibling `@CDKContainer`) so CDK-based stacks can participate in the same declarative flow as CloudFormation ones.

### 2. Configurable codegen

- [ ] Replace the "scan any .json for `AWSTemplateFormatVersion`" behaviour in `ContainerCodeGenPlugin` with an explicit configuration (manifest file or plugin arguments) listing template paths and the generated struct name for each.
- [ ] Support CDK-synthesized templates as an input to codegen.

### 3. Real-container LocalStack tests

- [ ] Add Docker integration test that exercises setup steps
- [ ] Replace mock-based LocalStack integration test with a real container test (validates CDK + codegen changes end-to-end).

### 4. Dockerfile-based service integration (design + build)

- [ ] Design a primitive for building an image from a Dockerfile and running it as a service container (e.g. `BuildImageSetup` / `ServiceContainer`), exposing ports and wait strategies.
- [ ] Design the debug-attach story for Swift services: remote LLDB from macOS into the Linux container over a forwarded port, targeting a Swift webapp/service defined in the same workspace as the tests. Non-Swift runtimes are explicitly out of scope.
- [ ] Implement once design is agreed.

### 5. Real-AWS deployment alternative

- [ ] Add a `ContainerSetup` alternative that runs CDK deploy against a real AWS account and returns the same `StackOutputs` shape — opt-in via env var so it stays off by default in CI.
- [ ] Document credential + cost tradeoffs.

## Integration Tests

- [x] Add Docker integration test that exercises wait strategies
