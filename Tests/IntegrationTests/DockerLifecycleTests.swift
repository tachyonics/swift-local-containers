import ContainerTestSupport
import DockerRuntime
import LocalContainers
import Testing

@Suite(.tags(.integration, .docker), .enabled(if: dockerAvailable, "Docker is required"))
struct DockerLifecycleTests {
    @Test("Full Docker container lifecycle: pull, create, start, inspect, stop, remove")
    func dockerLifecycle() async throws {
        let runtime = DockerContainerRuntime()

        // 1. Pull a small image
        try await runtime.pullImage("alpine:latest")

        // 2. Start a container with a port mapping
        let config = ContainerConfiguration(
            image: "alpine:latest",
            ports: [PortMapping(containerPort: 8080)],
            command: ["sleep", "30"]
        )
        let container = try await runtime.startContainer(from: config)

        // 3. Verify the running container has expected properties
        #expect(!container.id.isEmpty)
        #expect(!container.name.isEmpty)
        #expect(container.image == "alpine:latest")

        // 4. Stop and remove
        try await runtime.stopContainer(container)
        try await runtime.removeContainer(container)

        // 5. Verify the container is gone
        let client = DockerAPIClient()
        await #expect(throws: ContainerError.self) {
            _ = try await client.inspectContainer(id: container.id)
        }
    }

    @Test("startContainer fails fast with logs when the container exits immediately")
    func startContainerExitsImmediately() async throws {
        let runtime = DockerContainerRuntime()
        try await runtime.pullImage("alpine:latest")

        let config = ContainerConfiguration(
            image: "alpine:latest",
            ports: [PortMapping(containerPort: 8080)],
            command: ["sh", "-c", "echo 'goodbye cruel world' >&2; exit 7"]
        )

        await #expect {
            _ = try await runtime.startContainer(from: config)
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .startFailed(let reason) = containerError
            else {
                return false
            }
            return reason.contains("exit code: 7")
                && reason.contains("goodbye cruel world")
        }
    }
}
