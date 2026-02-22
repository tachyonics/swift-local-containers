import Testing

@testable import LocalContainers
@testable import LocalStack

@Suite("LocalStackContainer")
struct LocalStackContainerTests {
    @Test("Default configuration uses latest image and port 4566")
    func defaultConfig() {
        let ls = LocalStackContainer()
        let config = ls.configuration()

        #expect(config.image == "localstack/localstack:latest")
        #expect(config.ports.count == 1)
        #expect(config.ports[0].containerPort == 4566)
    }

    @Test("Services are joined into SERVICES env var")
    func servicesEnv() {
        let ls = LocalStackContainer(services: ["s3", "sqs", "dynamodb"])
        let config = ls.configuration()

        #expect(config.environment["SERVICES"] == "s3,sqs,dynamodb")
    }

    @Test("Custom image is preserved")
    func customImage() {
        let ls = LocalStackContainer(image: "localstack/localstack:3.0")
        let config = ls.configuration()

        #expect(config.image == "localstack/localstack:3.0")
    }

    @Test("Wait strategy is log-based")
    func waitStrategy() {
        let ls = LocalStackContainer()
        let config = ls.configuration()

        if case .log(let msg) = config.waitStrategy {
            #expect(msg == "Ready.")
        } else {
            Issue.record("Expected .log wait strategy")
        }
    }

    @Test("Additional environment variables are included")
    func additionalEnv() {
        let ls = LocalStackContainer(
            services: ["s3"],
            environment: ["LOCALSTACK_AUTH_TOKEN": "test-token"]
        )
        let config = ls.configuration()

        #expect(config.environment["LOCALSTACK_AUTH_TOKEN"] == "test-token")
        #expect(config.environment["SERVICES"] == "s3")
    }
}
