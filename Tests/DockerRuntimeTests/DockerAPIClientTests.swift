import AsyncHTTPClient
import LocalContainers
import Logging
import NIOCore
import NIOHTTP1
import Smockable
import Testing

@testable import DockerRuntime

@Smock
protocol TestHTTPExecutor: HTTPExecutor {
    func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount,
        logger: Logger?
    ) async throws -> HTTPClientResponse
}

private func makeResponse(
    status: HTTPResponseStatus,
    body: String
) -> HTTPClientResponse {
    HTTPClientResponse(
        status: status,
        body: .bytes(ByteBuffer(string: body))
    )
}

private func makeClient(
    returning response: HTTPClientResponse
) -> (client: GenericDockerAPIClient<MockTestHTTPExecutor>, mock: MockTestHTTPExecutor) {
    var expectations = MockTestHTTPExecutor.Expectations()
    when(expectations.execute(.any, timeout: .any, logger: .any), return: response)
    let mock = MockTestHTTPExecutor(expectations: expectations)
    let client = GenericDockerAPIClient(executor: mock)
    return (client, mock)
}

// MARK: - parseImageReference

@Suite("DockerAPIClient.parseImageReference")
struct ParseImageReferenceTests {
    @Test("Simple image without tag defaults to latest")
    func simpleImage() {
        let (image, tag) = DockerAPIClient.parseImageReference("nginx")
        #expect(image == "nginx")
        #expect(tag == "latest")
    }

    @Test("Image with tag")
    func imageWithTag() {
        let (image, tag) = DockerAPIClient.parseImageReference("nginx:1.25")
        #expect(image == "nginx")
        #expect(tag == "1.25")
    }

    @Test("Namespaced image with tag")
    func namespacedImageWithTag() {
        let (image, tag) = DockerAPIClient.parseImageReference("localstack/localstack:3.0")
        #expect(image == "localstack/localstack")
        #expect(tag == "3.0")
    }

    @Test("Registry with port and no tag defaults to latest")
    func registryWithPort() {
        let (image, tag) = DockerAPIClient.parseImageReference("registry:5000/myimage")
        #expect(image == "registry:5000/myimage")
        #expect(tag == "latest")
    }

    @Test("Registry with port and tag")
    func registryWithPortAndTag() {
        let (image, tag) = DockerAPIClient.parseImageReference("registry:5000/myimage:v2")
        #expect(image == "registry:5000/myimage")
        #expect(tag == "v2")
    }
}

// MARK: - pullImage

@Suite("DockerAPIClient.pullImage")
struct PullImageTests {
    @Test("NDJSON error in response body throws imagePullFailed")
    func ndjsonError() async {
        let body = """
            {"status": "Pulling..."}\n{"error": "unauthorized"}\n
            """
        let (client, mock) = makeClient(returning: makeResponse(status: .ok, body: body))

        await #expect {
            try await client.pullImage("nginx:latest")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .imagePullFailed(let image, let reason) = containerError
            else {
                return false
            }
            return image == "nginx:latest" && reason == "unauthorized"
        }

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/images/create") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("Non-2xx status after body consumed throws imagePullFailed")
    func nonSuccessStatus() async {
        let body = "{\"status\": \"Pulling...\"}\n"
        let (client, mock) = makeClient(
            returning: makeResponse(status: .internalServerError, body: body)
        )

        await #expect {
            try await client.pullImage("nginx:latest")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .imagePullFailed(let image, let reason) = containerError
            else {
                return false
            }
            return image == "nginx:latest" && reason == "HTTP 500"
        }

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/images/create") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("Success with whitespace-only body does not throw")
    func emptyBody() async throws {
        let (client, mock) = makeClient(returning: makeResponse(status: .ok, body: " \n"))
        try await client.pullImage("nginx:latest")

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/images/create") },
            timeout: .any,
            logger: .any
        )
    }
}

// MARK: - executeRequest error handling

@Suite("DockerAPIClient error handling")
struct ErrorHandlingTests {
    @Test("500 with Docker JSON error extracts message")
    func dockerJsonError() async {
        let body = "{\"message\": \"container is paused\"}"
        let (client, mock) = makeClient(
            returning: makeResponse(status: .internalServerError, body: body)
        )

        await #expect {
            try await client.removeContainer(id: "abc123")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .runtimeError(let msg) = containerError
            else {
                return false
            }
            return msg == "container is paused"
        }

        verify(mock).execute(
            .matching { $0.method == .DELETE && $0.url.contains("/containers/abc123") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("500 with plain text body falls back to HTTP status")
    func plainTextError() async {
        let body = "something went wrong"
        let (client, mock) = makeClient(
            returning: makeResponse(status: .internalServerError, body: body)
        )

        await #expect {
            try await client.startContainer(id: "abc123")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .runtimeError(let msg) = containerError
            else {
                return false
            }
            return msg == "HTTP 500"
        }

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/containers/abc123/start") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("404 on inspectContainer returns containerNotFound")
    func containerNotFoundInspect() async {
        let body = "{\"message\": \"No such container\"}"
        let (client, mock) = makeClient(returning: makeResponse(status: .notFound, body: body))

        await #expect {
            try await client.inspectContainer(id: "abc123")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .containerNotFound(let id) = containerError
            else {
                return false
            }
            return id == "abc123"
        }

        verify(mock).execute(
            .matching { $0.method == .GET && $0.url.contains("/containers/abc123/json") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("404 on stopContainer returns containerNotFound")
    func containerNotFoundStop() async {
        let body = "{\"message\": \"No such container\"}"
        let (client, mock) = makeClient(returning: makeResponse(status: .notFound, body: body))

        await #expect {
            try await client.stopContainer(id: "def456")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .containerNotFound(let id) = containerError
            else {
                return false
            }
            return id == "def456"
        }

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/containers/def456/stop") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("409 with Docker error message returns runtimeError")
    func conflictError() async {
        let body = "{\"message\": \"container already exists\"}"
        let (client, mock) = makeClient(returning: makeResponse(status: .conflict, body: body))

        let request = CreateContainerRequest(image: "nginx:latest")
        await #expect {
            try await client.createContainer(request, name: "test")
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .runtimeError(let msg) = containerError
            else {
                return false
            }
            return msg == "container already exists"
        }

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/containers/create") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("304 accepted by startContainer does not throw")
    func startContainerAlreadyStarted() async throws {
        let (client, mock) = makeClient(returning: makeResponse(status: .notModified, body: ""))
        try await client.startContainer(id: "abc123")

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/containers/abc123/start") },
            timeout: .any,
            logger: .any
        )
    }

    @Test("304 accepted by stopContainer does not throw")
    func stopContainerAlreadyStopped() async throws {
        let (client, mock) = makeClient(returning: makeResponse(status: .notModified, body: ""))
        try await client.stopContainer(id: "abc123")

        verify(mock).execute(
            .matching { $0.method == .POST && $0.url.contains("/containers/abc123/stop") },
            timeout: .any,
            logger: .any
        )
    }
}
