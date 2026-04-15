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
- [x] Make the deployment path transparently stub `/cdk-bootstrap/hnb659fds/version` in LocalStack (via the SSM `PutParameter` API) before `CreateStack`, using a bootstrap version value (`"20"`) that satisfies CDK's `CheckBootstrapVersion` rule. Extracted into `BootstrapVersionStub` and triggered automatically from `CloudFormationSetup` whenever the template body references the CDK bootstrap marker. User CDK apps require **zero** modification to be usable in tests AND production — the same stack definition (with `DefaultStackSynthesizer`) deploys cleanly to LocalStack for tests and to real CloudFormation for prod.
- [x] The `@LocalStackContainer` macro handles CDK-sourced `StackOutputs` structs uniformly — once `cdkapps[]` synthesizes a template at build time, the runtime deployment path is indistinguishable from a handwritten CF template. No separate `@CDKContainer` macro needed.
- [ ] Add an opt-in escape hatch for CDK stacks that use assets (Lambda inline code, Docker image assets, etc.) by invoking `cdklocal bootstrap` when `autoBootstrap: true`. This is the "advanced use case" path: slower (~30s for bootstrap) and introduces an `aws-cdk-local` npm dependency, but it's the only way to handle asset-bearing stacks against LocalStack.

### 2. Configurable codegen

- [x] Replace the "scan any .json for `AWSTemplateFormatVersion`" behaviour in `ContainerCodeGenPlugin` with an explicit `.local-containers/codegen.json` manifest listing template sources and generated struct names. Target scoping is implicit (plugin resolves each entry's `source` against every target's source directory and acts on matches).
- [x] Support CDK-synthesized templates as an input to codegen. Plugin handles `cdkapps[]` entries: invokes `ContainerCodeGenTool cdk-synth` which runs `npx cdk synth` at build time under the sandbox, stages the resulting template alongside the generated struct, and flows through the same codegen pipeline as handwritten templates. Build-time synth requires `node_modules/.bin/cdk` to exist in the CDK app directory — seeded once via the `bootstrap` command plugin.
- [x] Add `bootstrap` command plugin for one-time setup (currently: `npm install` for `cdkapps[]` entries). Lives outside the build sandbox with explicit `.allowNetworkConnections` + `.writeToPackageDirectory` permissions. Designed generically so future categories (docker image pre-pulls, Python virtualenvs, etc.) can be added as additional handler blocks without introducing new commands.

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
