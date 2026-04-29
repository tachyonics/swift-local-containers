import Testing

@testable import ContainerTestSupport
@testable import LocalContainers

@Suite("resolveEnvironment")
struct ResolveEnvironmentTests {
    @Test("Returns static environment unchanged when no provider")
    func noProvider() {
        let spec = ContainerSpec(
            ContainerConfiguration(
                image: "test:latest",
                environment: ["FOO": "1", "BAR": "2"]
            )
        )

        let result = resolveEnvironment(
            for: spec,
            started: [:],
            stackOutputs: [:],
            typedOutputs: [:]
        )

        #expect(result == ["FOO": "1", "BAR": "2"])
    }

    @Test("Provider's dict overlays static env — dynamic wins on collision")
    func dynamicOverlays() {
        let spec = ContainerSpec(
            ContainerConfiguration(
                image: "test:latest",
                environment: ["FOO": "static-1", "BAR": "static-2"]
            ),
            environmentProvider: {
                ["BAR": "dynamic-2", "BAZ": "dynamic-3"]
            }
        )

        let result = resolveEnvironment(
            for: spec,
            started: [:],
            stackOutputs: [:],
            typedOutputs: [:]
        )

        #expect(result == [
            "FOO": "static-1",
            "BAR": "dynamic-2",   // dynamic wins
            "BAZ": "dynamic-3"
        ])
    }

    @Test("Provider sees the partial ContainerTestContext during evaluation")
    func providerReadsPartialContext() {
        let siblingKey = ObjectIdentifier(SiblingKey.self)
        let siblingContainer = RunningContainer(
            id: "sibling-1",
            name: "sibling",
            image: "sibling:latest"
        )

        let spec = ContainerSpec(
            ContainerConfiguration(image: "test:latest"),
            environmentProvider: {
                guard let context = ContainerTestContext.current,
                    let outputs = context.outputs(for: siblingKey)
                else {
                    return ["CTX": "missing"]
                }
                return ["TABLE": outputs["TableName"] ?? "(no key)"]
            }
        )

        let result = resolveEnvironment(
            for: spec,
            started: [siblingKey: siblingContainer],
            stackOutputs: [siblingKey: ["TableName": "users-test"]],
            typedOutputs: [:]
        )

        #expect(result == ["TABLE": "users-test"])
    }

    @Test("ContainerTestContext.current is restored after the provider runs")
    func contextScopeReleased() async {
        let spec = ContainerSpec(
            ContainerConfiguration(image: "test:latest"),
            environmentProvider: { [:] }
        )

        // No outer context → should still be nil after resolveEnvironment returns.
        #expect(ContainerTestContext.current == nil)
        _ = resolveEnvironment(
            for: spec,
            started: [:],
            stackOutputs: [:],
            typedOutputs: [:]
        )
        #expect(ContainerTestContext.current == nil)
    }
}

private enum SiblingKey: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "sibling:latest")
    )
}
