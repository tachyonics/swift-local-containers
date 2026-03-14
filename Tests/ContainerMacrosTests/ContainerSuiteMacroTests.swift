import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ContainerMacros)
@testable import ContainerMacros

private let testMacros: [String: Macro.Type] = [
    "Containers": ContainerDeclarationsMacro.self,
    "Container": ContainerMacro.self,
    "LocalStackContainer": LocalStackContainerMacro.self,
]
#endif

final class ContainerDeclarationsMacroTests: XCTestCase {
    #if canImport(ContainerMacros)

    // MARK: - @Containers Member Macro

    func testContainersWithContainerProperty() throws {
        assertMacroExpansion(
            """
            @Containers
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testContainersWithLocalStackProperty() throws {
        assertMacroExpansion(
            """
            @Containers
            struct MyTests {
                @LocalStackContainer(stackName: "my-infra")
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
                            let templatePath = S3BucketTemplateOutputs.templatePath(relativeTo: #filePath)
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: S3BucketTemplateOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "my-infra"
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testContainersWithMultipleProperties() throws {
        assertMacroExpansion(
            """
            @Containers
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
                            let templatePath = S3BucketTemplateOutputs.templatePath(relativeTo: #filePath)
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testContainersWithMultiplePorts() throws {
        assertMacroExpansion(
            """
            @Containers
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testContainersWithNoAnnotatedProperties() throws {
        assertMacroExpansion(
            """
            @Containers
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
            @Containers
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testLocalStackContainerWithDefaultStackName() throws {
        assertMacroExpansion(
            """
            @Containers
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
                            let templatePath = SomeOutputs.templatePath(relativeTo: #filePath)
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Non-variable Members

    func testContainersIgnoresUnannotatedMembers() throws {
        assertMacroExpansion(
            """
            @Containers
            struct MyTests {
                func helper() {}

                var name: String

                @Container(image: "redis:7", ports: [6379])
                var cache: RunningContainer
            }
            """,
            expandedSource: """
                struct MyTests {
                    func helper() {}

                    var name: String
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

                extension MyTests: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Enum with Static Properties

    func testContainersOnEnumWithStaticContainer() throws {
        assertMacroExpansion(
            """
            @Containers
            enum MyContainers {
                @Container(image: "postgres:16", ports: [5432])
                static var db: RunningContainer
            }
            """,
            expandedSource: """
                enum MyContainers {
                    static var db: RunningContainer {
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

                extension MyContainers: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testContainersOnEnumWithStaticLocalStack() throws {
        assertMacroExpansion(
            """
            @Containers
            enum MyContainers {
                @LocalStackContainer(stackName: "infra")
                static var stack: S3BucketOutputs
            }
            """,
            expandedSource: """
                enum MyContainers {
                    static var stack: S3BucketOutputs {
                        get {
                            guard let output: S3BucketOutputs = ContainerTestContext.current?.output(
                                for: ObjectIdentifier(_StackKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return output
                        }
                    }

                    private enum _StackKey: ContainerKey {
                        static let spec: ContainerSpec = {
                            let templatePath = S3BucketOutputs.templatePath(relativeTo: #filePath)
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: S3BucketOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "infra"
                                    ),
                                ]
                            )
                        }()
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_StackKey.self, outputConstructor: {
                                    try S3BucketOutputs(rawOutputs: $0)
                                })],
                        runtime: PlatformRuntime()
                    )
                }

                extension MyContainers: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Struct with Instance Properties

    func testContainersOnStructWithInstanceContainer() throws {
        assertMacroExpansion(
            """
            @Containers
            struct MyContainers {
                @Container(image: "postgres:16", ports: [5432])
                var db: RunningContainer
            }
            """,
            expandedSource: """
                struct MyContainers {
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

                extension MyContainers: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    func testContainersOnStructWithInstanceLocalStack() throws {
        assertMacroExpansion(
            """
            @Containers
            struct MyContainers {
                @LocalStackContainer(stackName: "infra")
                var stack: S3BucketOutputs
            }
            """,
            expandedSource: """
                struct MyContainers {
                    var stack: S3BucketOutputs {
                        get {
                            guard let output: S3BucketOutputs = ContainerTestContext.current?.output(
                                for: ObjectIdentifier(_StackKey.self)
                            ) else {
                                preconditionFailure(
                                    "No container context — is this test inside a @Suite with containerTrait?"
                                )
                            }
                            return output
                        }
                    }

                    private enum _StackKey: ContainerKey {
                        static let spec: ContainerSpec = {
                            let templatePath = S3BucketOutputs.templatePath(relativeTo: #filePath)
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: S3BucketOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "infra"
                                    ),
                                ]
                            )
                        }()
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_StackKey.self, outputConstructor: {
                                    try S3BucketOutputs(rawOutputs: $0)
                                })],
                        runtime: PlatformRuntime()
                    )
                }

                extension MyContainers: ContainerDeclarations {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Shared Containers (peer enum, multiple suites)

    func testSharedContainersWithMultipleStaticProperties() throws {
        assertMacroExpansion(
            """
            @Containers
            enum SharedContainers {
                @Container(image: "postgres:16", ports: [5432])
                static var db: RunningContainer

                @LocalStackContainer(stackName: "shared-stack")
                static var stack: MyOutputs
            }
            """,
            expandedSource: """
                enum SharedContainers {
                    static var db: RunningContainer {
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
                    static var stack: MyOutputs {
                        get {
                            guard let output: MyOutputs = ContainerTestContext.current?.output(
                                for: ObjectIdentifier(_StackKey.self)
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

                    private enum _StackKey: ContainerKey {
                        static let spec: ContainerSpec = {
                            let templatePath = MyOutputs.templatePath(relativeTo: #filePath)
                            return ContainerSpec(
                                LocalStackContainer(
                                    services: MyOutputs.requiredServices
                                ).configuration(),
                                setups: [
                                    CloudFormationSetup(
                                        templatePath: templatePath,
                                        stackName: "shared-stack"
                                    ),
                                ]
                            )
                        }()
                    }

                    static let containerTrait = ContainerTrait(
                        keys: [ErasedContainerKey(_DbKey.self), ErasedContainerKey(_StackKey.self, outputConstructor: {
                                    try MyOutputs(rawOutputs: $0)
                                })],
                        runtime: PlatformRuntime()
                    )
                }

                extension SharedContainers: ContainerDeclarations {
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
