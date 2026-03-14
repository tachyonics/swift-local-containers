import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ContainerMacros)
@testable import ContainerMacros

private let testMacros: [String: Macro.Type] = [
    "ContainerSuite": ContainerSuiteMacro.self,
    "Container": ContainerMacro.self,
    "LocalStackContainer": LocalStackContainerMacro.self,
]
#endif

final class ContainerSuiteMacroTests: XCTestCase {
    #if canImport(ContainerMacros)

    // MARK: - @ContainerSuite Member Macro

    func testContainerSuiteWithContainerProperty() throws {
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
                    var db: RunningContainer {
                        get {
                            guard let container = try? ContainerTestContext.current?.container(
                                for: ObjectIdentifier(_DbKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return container
                        }
                    }

                    private enum _DbKey: ContainerKey {
                        static let spec = ContainerSpec(
                            ContainerConfiguration(
                                image: "postgres:16",
                                ports: [PortMapping(containerPort: 5432)]
                            )
                        )
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_DbKey.self)],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    func testContainerSuiteWithLocalStackProperty() throws {
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
                    var aws: S3BucketTemplateOutputs {
                        get {
                            guard let output: S3BucketTemplateOutputs = ContainerTestContext.current?.output(
                                for: ObjectIdentifier(_AwsKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return output
                        }
                    }

                    private enum _AwsKey: ContainerKey {
                        static let spec: ContainerSpec = {
                            let templatePath = URL(fileURLWithPath: #filePath)
                                .deletingLastPathComponent()
                                .appendingPathComponent("Resources")
                                .appendingPathComponent(S3BucketTemplateOutputs.templateFileName)
                                .path
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: S3BucketTemplateOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "test-stack"
                                    ),
                                ]
                            )
                        }()
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_AwsKey.self, outputConstructor: {
                                    try S3BucketTemplateOutputs(rawOutputs: $0)
                                })],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    func testContainerSuiteWithMultipleProperties() throws {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                @Container(image: "postgres:16", ports: [5432])
                var db: RunningContainer

                @LocalStackContainer(stackName: "my-stack")
                var aws: S3BucketTemplateOutputs
            }
            """,
            expandedSource: """
                struct MyTests {
                    var db: RunningContainer {
                        get {
                            guard let container = try? ContainerTestContext.current?.container(
                                for: ObjectIdentifier(_DbKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return container
                        }
                    }
                    var aws: S3BucketTemplateOutputs {
                        get {
                            guard let output: S3BucketTemplateOutputs = ContainerTestContext.current?.output(
                                for: ObjectIdentifier(_AwsKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return output
                        }
                    }

                    private enum _DbKey: ContainerKey {
                        static let spec = ContainerSpec(
                            ContainerConfiguration(
                                image: "postgres:16",
                                ports: [PortMapping(containerPort: 5432)]
                            )
                        )
                    }

                    private enum _AwsKey: ContainerKey {
                        static let spec: ContainerSpec = {
                            let templatePath = URL(fileURLWithPath: #filePath)
                                .deletingLastPathComponent()
                                .appendingPathComponent("Resources")
                                .appendingPathComponent(S3BucketTemplateOutputs.templateFileName)
                                .path
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: S3BucketTemplateOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "my-stack"
                                    ),
                                ]
                            )
                        }()
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_DbKey.self), ErasedContainerKey(_AwsKey.self, outputConstructor: {
                                    try S3BucketTemplateOutputs(rawOutputs: $0)
                                })],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    func testContainerSuiteWithMultiplePorts() throws {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                @Container(image: "app:latest", ports: [8080, 8443])
                var app: RunningContainer
            }
            """,
            expandedSource: """
                struct MyTests {
                    var app: RunningContainer {
                        get {
                            guard let container = try? ContainerTestContext.current?.container(
                                for: ObjectIdentifier(_AppKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return container
                        }
                    }

                    private enum _AppKey: ContainerKey {
                        static let spec = ContainerSpec(
                            ContainerConfiguration(
                                image: "app:latest",
                                ports: [PortMapping(containerPort: 8080), PortMapping(containerPort: 8443)]
                            )
                        )
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_AppKey.self)],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    func testContainerSuiteWithNoAnnotatedProperties() throws {
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
            macros: testMacros
        )
    }

    // MARK: - @LocalStackContainer Accessor Edge Cases

    func testLocalStackContainerWithoutTypeAnnotation() throws {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                @LocalStackContainer(stackName: "test")
                var aws
            }
            """,
            expandedSource: """
                struct MyTests {
                    var aws



                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_AwsKey.self)],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    func testLocalStackContainerWithDefaultStackName() throws {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                @LocalStackContainer()
                var aws: SomeOutputs
            }
            """,
            expandedSource: """
                struct MyTests {
                    var aws: SomeOutputs {
                        get {
                            guard let output: SomeOutputs = ContainerTestContext.current?.output(
                                for: ObjectIdentifier(_AwsKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return output
                        }
                    }

                    private enum _AwsKey: ContainerKey {
                        static let spec: ContainerSpec = {
                            let templatePath = URL(fileURLWithPath: #filePath)
                                .deletingLastPathComponent()
                                .appendingPathComponent("Resources")
                                .appendingPathComponent(SomeOutputs.templateFileName)
                                .path
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: SomeOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "test-stack"
                                    ),
                                ]
                            )
                        }()
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_AwsKey.self, outputConstructor: {
                                    try SomeOutputs(rawOutputs: $0)
                                })],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - @ContainerSuite with non-variable members

    func testContainerSuiteIgnoresNonVariableMembers() throws {
        assertMacroExpansion(
            """
            @ContainerSuite
            struct MyTests {
                func helper() {}

                @Container(image: "redis:7", ports: [6379])
                var cache: RunningContainer
            }
            """,
            expandedSource: """
                struct MyTests {
                    func helper() {}
                    var cache: RunningContainer {
                        get {
                            guard let container = try? ContainerTestContext.current?.container(
                                for: ObjectIdentifier(_CacheKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return container
                        }
                    }

                    private enum _CacheKey: ContainerKey {
                        static let spec = ContainerSpec(
                            ContainerConfiguration(
                                image: "redis:7",
                                ports: [PortMapping(containerPort: 6379)]
                            )
                        )
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_CacheKey.self)],
                        runtime: PlatformRuntime()
                    )
                }
                """,
            macros: testMacros
        )
    }

    #else
    func testMacrosUnavailable() throws {
        XCTSkip("Macros are only supported when running the tests from the package")
    }
    #endif
}
