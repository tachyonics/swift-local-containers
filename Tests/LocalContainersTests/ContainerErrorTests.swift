import Testing

@testable import LocalContainers

@Suite("ContainerError")
struct ContainerErrorTests {
    @Test("imagePullFailed carries image and reason")
    func imagePullFailed() {
        let error = ContainerError.imagePullFailed(image: "nginx:latest", reason: "not found")

        if case .imagePullFailed(let image, let reason) = error {
            #expect(image == "nginx:latest")
            #expect(reason == "not found")
        } else {
            Issue.record("Expected .imagePullFailed")
        }
    }

    @Test("startFailed carries reason")
    func startFailed() {
        let error = ContainerError.startFailed(reason: "port conflict")

        if case .startFailed(let reason) = error {
            #expect(reason == "port conflict")
        } else {
            Issue.record("Expected .startFailed")
        }
    }

    @Test("healthCheckFailed carries reason")
    func healthCheckFailed() {
        let error = ContainerError.healthCheckFailed(reason: "timeout")

        if case .healthCheckFailed(let reason) = error {
            #expect(reason == "timeout")
        } else {
            Issue.record("Expected .healthCheckFailed")
        }
    }

    @Test("waitStrategyTimedOut carries strategy and timeout")
    func waitStrategyTimedOut() {
        let error = ContainerError.waitStrategyTimedOut(
            strategy: "port",
            timeout: .seconds(30)
        )

        if case .waitStrategyTimedOut(let strategy, let timeout) = error {
            #expect(strategy == "port")
            #expect(timeout == .seconds(30))
        } else {
            Issue.record("Expected .waitStrategyTimedOut")
        }
    }

    @Test("containerExitedDuringWait carries exit code")
    func containerExitedDuringWait() {
        let error = ContainerError.containerExitedDuringWait(exitCode: 1)

        if case .containerExitedDuringWait(let exitCode) = error {
            #expect(exitCode == 1)
        } else {
            Issue.record("Expected .containerExitedDuringWait")
        }
    }

    @Test("portNotFound carries container port")
    func portNotFound() {
        let error = ContainerError.portNotFound(containerPort: 8080)

        if case .portNotFound(let port) = error {
            #expect(port == 8080)
        } else {
            Issue.record("Expected .portNotFound")
        }
    }

    @Test("runtimeError carries message")
    func runtimeError() {
        let error = ContainerError.runtimeError("unexpected failure")

        if case .runtimeError(let msg) = error {
            #expect(msg == "unexpected failure")
        } else {
            Issue.record("Expected .runtimeError")
        }
    }

    @Test("setupFailed carries step and reason")
    func setupFailed() {
        let error = ContainerError.setupFailed(step: "CloudFormation", reason: "template invalid")

        if case .setupFailed(let step, let reason) = error {
            #expect(step == "CloudFormation")
            #expect(reason == "template invalid")
        } else {
            Issue.record("Expected .setupFailed")
        }
    }

    @Test("containerNotFound carries id")
    func containerNotFound() {
        let error = ContainerError.containerNotFound(id: "abc123")

        if case .containerNotFound(let id) = error {
            #expect(id == "abc123")
        } else {
            Issue.record("Expected .containerNotFound")
        }
    }

    @Test("description renders every case")
    func descriptions() {
        #expect(
            ContainerError.imagePullFailed(image: "nginx:latest", reason: "not found").description
                == "Failed to pull image 'nginx:latest': not found"
        )
        #expect(
            ContainerError.startFailed(reason: "port conflict").description
                == "Container failed to start: port conflict"
        )
        #expect(
            ContainerError.healthCheckFailed(reason: "timeout").description
                == "Health check failed: timeout"
        )
        #expect(
            ContainerError.waitStrategyTimedOut(strategy: "port", timeout: .seconds(30))
                .description
                == "Wait strategy 'port' timed out after \(Duration.seconds(30))"
        )
        #expect(
            ContainerError.containerExitedDuringWait(exitCode: 137).description
                == "Container exited unexpectedly with code 137"
        )
        #expect(
            ContainerError.containerExitedDuringWait(exitCode: nil).description
                == "Container exited unexpectedly"
        )
        #expect(
            ContainerError.portNotFound(containerPort: 8080).description
                == "No port mapping found for container port 8080"
        )
        #expect(
            ContainerError.runtimeError("boom").description
                == "Container runtime error: boom"
        )
        #expect(
            ContainerError.setupFailed(step: "bootstrap", reason: "bad").description
                == "Setup step 'bootstrap' failed: bad"
        )
        #expect(
            ContainerError.containerNotFound(id: "abc123").description
                == "Container not found: abc123"
        )
    }
}
