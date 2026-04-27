import Foundation
import Testing

@testable import LocalContainers
@testable import LocalStack

@Suite("LocalStackContainer")
struct LocalStackContainerTests {
    @Test("Default configuration uses latest image and port 4566")
    func defaultConfig() {
        let ls = LocalStackContainer()
        let config = ls.configuration()

        #expect(config.image.imageReference == "localstack/localstack:latest")
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

        #expect(config.image.imageReference == "localstack/localstack:3.0")
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

    @Test("DEBUG=1 is set when no auth token is provided")
    func debugWhenNoToken() {
        let ls = LocalStackContainer()
        let config = ls.configuration()

        #expect(config.environment["DEBUG"] == "1")
        #expect(config.environment["LOCALSTACK_AUTH_TOKEN"] == nil)
    }

    @Test("DEBUG is not overridden when auth token is provided")
    func noDebugWhenTokenPresent() {
        let ls = LocalStackContainer(
            environment: ["LOCALSTACK_AUTH_TOKEN": "t"]
        )
        let config = ls.configuration()

        #expect(config.environment["DEBUG"] == nil)
    }

    @Test("configuration does not read from process environment")
    func configurationIgnoresProcessEnv() {
        // LOCALSTACK_AUTH_TOKEN is usually set in the shell for contributors;
        // the pure `configuration()` must not pick it up implicitly.
        let ls = LocalStackContainer()
        let config = ls.configuration()

        #expect(config.environment["LOCALSTACK_AUTH_TOKEN"] == nil)
    }

    @Test("environmentForwarding overlays shell values on baseline")
    func environmentForwardingOverlays() {
        // No shell override for these keys, so baseline values pass through.
        let merged = LocalStackContainer.environmentForwarding(
            ["NONEXISTENT_KEY_FOR_TEST"],
            overriding: ["NONEXISTENT_KEY_FOR_TEST": "from-baseline", "OTHER": "value"]
        )

        #expect(merged["NONEXISTENT_KEY_FOR_TEST"] == "from-baseline")
        #expect(merged["OTHER"] == "value")
    }

    @Test("environmentForwarding omits missing keys")
    func environmentForwardingSkipsMissing() {
        let merged = LocalStackContainer.environmentForwarding(
            ["DEFINITELY_NOT_SET_\(UUID().uuidString)"]
        )
        #expect(merged.isEmpty)
    }
}
