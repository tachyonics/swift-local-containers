# TODO

## ContainerizationRuntime

- [ ] Implement `pullImage()` using `Containerization.Image` to pull OCI images
- [ ] Implement `startContainer()` to create and start a VM with the container image
- [ ] Implement `stopContainer()` to stop the VM
- [ ] Implement `removeContainer()` to remove the VM and clean up resources
- [ ] Implement `ContainerizationManager` actor for VM/image lifecycle
- [ ] Add unit tests for ContainerizationRuntime

## Wait Strategies

- [x] Implement wait strategy polling in `ContainerTrait` before handing control to tests
- [x] Implement port connectivity check (`.port`)
- [x] Implement health check polling via inspect loop (`.healthCheck`)
- [x] Implement log output monitoring (`.logMessage`)
- [x] Implement fixed delay (`.fixedDelay`)
- [x] Implement custom closure wait (`.custom`)
- [x] Add timeout handling for wait strategies

## LocalStack Setup Steps

- [ ] Implement `CloudFormationSetup.createStack()` — POST to CloudFormation API with `Action=CreateStack`
- [ ] Implement `CloudFormationSetup.waitForStack()` — poll `DescribeStacks` until `CREATE_COMPLETE`
- [ ] Implement `CloudFormationSetup.deleteStack()` — POST with `Action=DeleteStack`
- [ ] Implement `CDKSetup.runShell()` using `Foundation.Process` to run `cdk bootstrap`, `cdk synth`, etc.
- [ ] Add functional tests for CloudFormation and CDK setup steps

## Integration Tests

- [ ] Add Docker integration test that exercises wait strategies
- [ ] Add Docker integration test that exercises setup steps
- [ ] Replace mock-based LocalStack integration test with a real container test
- [ ] Add ContainerizationRuntime integration test (macOS 26+)
