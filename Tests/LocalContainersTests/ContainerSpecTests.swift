import Testing

@testable import LocalContainers

private struct NoOpSetup: ContainerSetup {
    func setUp(container: RunningContainer) async throws {}
}

@Suite("ContainerSpec")
struct ContainerSpecTests {
    @Test("Spec holds configuration and setups")
    func specWithSetups() {
        let config = ContainerConfiguration(image: "redis:7")
        let spec = ContainerSpec(config, setups: [NoOpSetup()])

        #expect(spec.configuration.image == "redis:7")
        #expect(spec.setups.count == 1)
    }

    @Test("Spec defaults to empty setups")
    func specWithoutSetups() {
        let config = ContainerConfiguration(image: "redis:7")
        let spec = ContainerSpec(config)

        #expect(spec.setups.isEmpty)
    }
}
