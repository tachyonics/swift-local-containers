import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import ContainerMacros

@Suite("ContainerSuiteMacro")
struct ContainerSuiteMacroTests {
    private let macros: [String: any Macro.Type] = [
        "ContainerSuite": ContainerSuiteMacro.self,
        "Container": ContainerMacro.self,
        "LocalStackContainer": LocalStackContainerMacro.self
    ]

    @Test("Generates key, trait impl, and containerTrait for @Container property")
    func containerProperty() {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                @Container(image: "postgres:16", ports: [5432])
                var db: RunningContainer
            }
            """,
            expandedSource: """
                struct MyTests {
                    @Container(image: "postgres:16", ports: [5432])
                    var db: RunningContainer {
                        get throws {
                            let ctx = try ContainerTestContext.requireCurrent()
                            return try ctx.container(for: ObjectIdentifier(_DbKey.self))
                        }
                    }

                    enum _DbKey: ContainerKey {
                        static let spec = ContainerSpec(ContainerConfiguration(image: "postgres:16", ports: [PortMapping(containerPort: 5432)]))
                    }

                    struct _ContainerTraitImpl: SuiteTrait, TestScoping {
                        let isRecursive = true

                        func provideScope(
                            for test: Test,
                            testCase: Test.Case?,
                            performing execute: @Sendable () async throws -> Void
                        ) async throws {
                            guard testCase == nil else {
                                try await execute()
                                return
                            }

                            let runtime = PlatformRuntime()
                            let logger = Logger(label: "ContainerTrait")

                            let dbSpec = _DbKey.spec
                            logger.info("Starting container", metadata: ["image": "\\(dbSpec.configuration.image)"])
                            try await runtime.pullImage(dbSpec.configuration.image)
                            let dbContainer = try await runtime.startContainer(from: dbSpec.configuration)

                            try await WaitStrategyExecutor.waitUntilReady(
                                container: dbContainer,
                                configuration: dbSpec.configuration,
                                runtime: runtime
                            )

                            for setup in dbSpec.setups {
                                try await setup.setUp(container: dbContainer)
                            }

                            let context = ContainerTestContext(
                                containers: [
                                    ObjectIdentifier(_DbKey.self): dbContainer
                                ],
                                stackOutputs: [:]
                            )
                            do {
                                try await ContainerTestContext.$current.withValue(context) {
                                    try await execute()
                                }
                            } catch {
                                logger.error("Container lifecycle error", metadata: ["error": "\\(error)"])
                                throw error
                            }

                            for setup in dbSpec.setups {
                                try? await setup.tearDown(container: dbContainer)
                            }
                            do {
                                try await runtime.stopContainer(dbContainer)
                                try await runtime.removeContainer(dbContainer)
                            } catch {
                                logger.warning("Failed to clean up container", metadata: ["id": "\\(dbContainer.id)", "error": "\\(error)"])
                            }
                        }
                    }

                    static let containerTrait = _ContainerTraitImpl()
                }
                """,
            macros: macros
        )
    }

    @Test("Generates accessor for @LocalStackContainer property")
    func localStackContainerAccessor() {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                @LocalStackContainer(stackName: "test-stack")
                var aws: S3BucketTemplateOutputs
            }
            """,
            expandedSource: """
                struct MyTests {
                    @LocalStackContainer(stackName: "test-stack")
                    var aws: S3BucketTemplateOutputs {
                        get throws {
                            let ctx = try ContainerTestContext.requireCurrent()
                            guard let rawOutputs = ctx.outputs(for: ObjectIdentifier(_AwsKey.self)) else {
                                throw StackOutputError.outputsNotAvailable(stackName: "test-stack")
                            }
                            return try S3BucketTemplateOutputs(rawOutputs: rawOutputs)
                        }
                    }

                    enum _AwsKey: ContainerKey {
                        static let spec = ContainerSpec(LocalStackContainer(services: S3BucketTemplateOutputs.requiredServices).configuration())
                    }

                    struct _ContainerTraitImpl: SuiteTrait, TestScoping {
                        let isRecursive = true

                        func provideScope(
                            for test: Test,
                            testCase: Test.Case?,
                            performing execute: @Sendable () async throws -> Void
                        ) async throws {
                            guard testCase == nil else {
                                try await execute()
                                return
                            }

                            let runtime = PlatformRuntime()
                            let logger = Logger(label: "ContainerTrait")

                            let awsSpec = _AwsKey.spec
                            logger.info("Starting container", metadata: ["image": "\\(awsSpec.configuration.image)"])
                            try await runtime.pullImage(awsSpec.configuration.image)
                            let awsContainer = try await runtime.startContainer(from: awsSpec.configuration)

                            try await WaitStrategyExecutor.waitUntilReady(
                                container: awsContainer,
                                configuration: awsSpec.configuration,
                                runtime: runtime
                            )

                            for setup in awsSpec.setups {
                                try await setup.setUp(container: awsContainer)
                            }
                            let awsEndpoint = try LocalStackEndpoint(container: awsContainer).awsEndpoint()
                            let awsFetcher = CloudFormationSetup(templatePath: "", stackName: "test-stack")
                            let awsRawOutputs = try await awsFetcher.fetchOutputs(endpoint: awsEndpoint)

                            let context = ContainerTestContext(
                                containers: [
                                    ObjectIdentifier(_AwsKey.self): awsContainer
                                ],
                                stackOutputs: [ObjectIdentifier(_AwsKey.self): awsRawOutputs]
                            )
                            do {
                                try await ContainerTestContext.$current.withValue(context) {
                                    try await execute()
                                }
                            } catch {
                                logger.error("Container lifecycle error", metadata: ["error": "\\(error)"])
                                throw error
                            }

                            for setup in awsSpec.setups {
                                try? await setup.tearDown(container: awsContainer)
                            }
                            do {
                                try await runtime.stopContainer(awsContainer)
                                try await runtime.removeContainer(awsContainer)
                            } catch {
                                logger.warning("Failed to clean up container", metadata: ["id": "\\(awsContainer.id)", "error": "\\(error)"])
                            }
                        }
                    }

                    static let containerTrait = _ContainerTraitImpl()
                }
                """,
            macros: macros
        )
    }

    @Test("Errors when applied to non-struct")
    func errorOnNonStruct() {
        assertMacroExpansion(
            """
            @ContainerSuite
            class MyTests {
                @Container(image: "postgres:16")
                var db: RunningContainer
            }
            """,
            expandedSource: """
                class MyTests {
                    @Container(image: "postgres:16")
                    var db: RunningContainer
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ContainerSuite can only be applied to a struct",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    @Test("Errors when no container properties found")
    func errorOnNoProperties() {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                var name: String
            }
            """,
            expandedSource: """
                struct MyTests {
                    var name: String
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ContainerSuite requires at least one @Container or @LocalStackContainer property",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }
}
