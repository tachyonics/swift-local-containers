import AsyncHTTPClient
import ContainerMacrosLib
import ContainerTestSupport
import Foundation
import NIOCore
import Testing

/// End-to-end verification that `@DockerfileContainer(environment:)` reaches
/// the running container. The fixture is a tiny alpine + busybox `nc` server
/// that echoes `$INJECTED_VAR` as the HTTP body; the test injects a literal
/// value via the closure and checks the response.
///
/// Cross-container-from-real-siblings (closure reading another container's
/// outputs) is exercised via task-cluster's integration test against
/// LocalStack DDB. This in-repo test stays minimal — single container, literal
/// env value — to catch regressions in the macro/trait/spec wiring without
/// adding a heavy fixture.
@Containers
struct EnvInjectionContainers {
    @DockerfileContainer(
        context: "Tests/IntegrationTests/Resources/env-echo",
        environment: { (_: EnvInjectionContainers) in
            ["INJECTED_VAR": "hello-from-environment-closure"]
        }
    )
    var service: ServiceEndpoint
}

@Suite(
    EnvInjectionContainers.containerTrait,
    .tags(.integration, .docker),
    .enabled(if: dockerAvailable, "Docker is required")
)
struct EnvInjectionIntegrationTests {
    let containers = EnvInjectionContainers()

    @Test("environment closure value reaches the running container as an env var")
    func envInjectionEndToEnd() async throws {
        let baseURL = containers.service.baseURL

        let response = try await HTTPClient.shared.execute(
            HTTPClientRequest(url: baseURL),
            timeout: .seconds(5)
        )
        let body = try await response.body.collect(upTo: 1024)

        #expect(response.status == .ok)
        #expect(String(buffer: body) == "hello-from-environment-closure")
    }
}
