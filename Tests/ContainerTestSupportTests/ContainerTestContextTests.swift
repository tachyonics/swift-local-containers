import Testing

@testable import ContainerTestSupport
@testable import LocalContainers

private struct FakeDB: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "postgres:16", ports: [PortMapping(containerPort: 5432)])
    )
}

private struct FakeCache: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "redis:7", ports: [PortMapping(containerPort: 6379)])
    )
}

private struct Unregistered: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "nginx:latest")
    )
}

@Suite("ContainerTestContext")
struct ContainerTestContextTests {
    private static let dbContainer = RunningContainer(
        id: "pg-1",
        name: "postgres",
        image: "postgres:16",
        ports: [ResolvedPortMapping(containerPort: 5432, hostPort: 54320)]
    )

    private static let cacheContainer = RunningContainer(
        id: "redis-1",
        name: "redis",
        image: "redis:7",
        ports: [ResolvedPortMapping(containerPort: 6379, hostPort: 63790)]
    )

    @Test("Subscript returns the correct container for a key")
    func lookupByKey() throws {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer,
            ObjectIdentifier(FakeCache.self): Self.cacheContainer,
        ])

        let db = try ctx[FakeDB.self]
        #expect(db.id == "pg-1")
        #expect(db.image == "postgres:16")

        let cache = try ctx[FakeCache.self]
        #expect(cache.id == "redis-1")
    }

    @Test("Subscript throws for an unregistered key")
    func lookupMissingKey() {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer
        ])

        #expect(throws: ContainerError.self) {
            try ctx[Unregistered.self]
        }
    }

    @Test("Empty context throws for any lookup")
    func emptyContext() {
        let ctx = ContainerTestContext(containers: [:])

        #expect(throws: ContainerError.self) {
            try ctx[FakeDB.self]
        }
    }

    @Test("TaskLocal current is nil by default")
    func taskLocalDefault() {
        #expect(ContainerTestContext.current == nil)
    }

    @Test("TaskLocal current is set within withValue scope")
    func taskLocalWithValue() async {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer
        ])

        ContainerTestContext.$current.withValue(ctx) {
            let current = ContainerTestContext.current
            #expect(current != nil)
            let db = try? current?[FakeDB.self]
            #expect(db?.id == "pg-1")
        }

        #expect(ContainerTestContext.current == nil)
    }
}
