import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@ContainerSuite` — Generates container keys, a concrete `SuiteTrait` implementation,
/// and a `containerTrait` static property for the annotated struct.
///
/// Scans member properties annotated with `@Container` or `@LocalStackContainer`,
/// generates a `ContainerKey` enum for each, and a concrete `_ContainerTraitImpl`
/// struct that avoids existential storage entirely.
public struct ContainerSuiteMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError("@ContainerSuite can only be applied to a struct")
        }

        // Find all properties with @Container or @LocalStackContainer attributes
        var containerProperties: [ContainerProperty] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let propName = pattern.identifier.text

                // Check for @Container attribute
                if let attr = findAttribute(named: "Container", in: varDecl) {
                    let args = parseContainerArgs(attr)
                    containerProperties.append(
                        ContainerProperty(
                            name: propName,
                            kind: .container(args),
                            typeAnnotation: binding.typeAnnotation?.type.trimmedDescription
                        )
                    )
                }

                // Check for @LocalStackContainer attribute
                if let attr = findAttribute(named: "LocalStackContainer", in: varDecl) {
                    let args = parseLocalStackContainerArgs(attr)
                    containerProperties.append(
                        ContainerProperty(
                            name: propName,
                            kind: .localStack(args),
                            typeAnnotation: binding.typeAnnotation?.type.trimmedDescription
                        )
                    )
                }
            }
        }

        guard !containerProperties.isEmpty else {
            throw MacroError("@ContainerSuite requires at least one @Container or @LocalStackContainer property")
        }

        var declarations: [DeclSyntax] = []

        // Generate a ContainerKey enum for each property
        for prop in containerProperties {
            let keyName = "_\(capitalizeFirst(prop.name))Key"
            let specDecl = generateSpec(for: prop)
            declarations.append(
                """
                enum \(raw: keyName): ContainerKey {
                    static let spec = \(raw: specDecl)
                }
                """
            )
        }

        // Generate _ContainerTraitImpl
        let traitImpl = generateTraitImpl(properties: containerProperties)
        declarations.append(contentsOf: traitImpl)

        // Generate static let containerTrait
        declarations.append(
            """
            static let containerTrait = _ContainerTraitImpl()
            """
        )

        return declarations
    }
}

// MARK: - Property Model

struct ContainerProperty {
    let name: String
    let kind: Kind
    let typeAnnotation: String?

    enum Kind {
        case container(ContainerArgs)
        case localStack(LocalStackArgs)
    }
}

struct ContainerArgs {
    let image: String
    let ports: [String]
    let environment: [(String, String)]
    let waitStrategy: String?
}

struct LocalStackArgs {
    let stackName: String
    let parameters: [(String, String)]
}

// MARK: - Argument Parsing

private func findAttribute(named name: String, in varDecl: VariableDeclSyntax) -> AttributeSyntax? {
    for attr in varDecl.attributes {
        if let attribute = attr.as(AttributeSyntax.self),
            let ident = attribute.attributeName.as(IdentifierTypeSyntax.self),
            ident.name.text == name
        {
            return attribute
        }
    }
    return nil
}

private func parseContainerArgs(_ attr: AttributeSyntax) -> ContainerArgs {
    var image = ""
    var ports: [String] = []
    var environment: [(String, String)] = []
    var waitStrategy: String?

    if let args = attr.arguments?.as(LabeledExprListSyntax.self) {
        for arg in args {
            switch arg.label?.text {
            case "image":
                image = extractStringLiteral(arg.expression) ?? ""
            case "ports":
                ports = extractArrayLiteral(arg.expression)
            case "environment":
                environment = extractDictionaryLiteral(arg.expression)
            case "waitStrategy":
                waitStrategy = arg.expression.trimmedDescription
            default:
                break
            }
        }
    }

    return ContainerArgs(image: image, ports: ports, environment: environment, waitStrategy: waitStrategy)
}

private func parseLocalStackContainerArgs(_ attr: AttributeSyntax) -> LocalStackArgs {
    var stackName = "test-stack"
    var parameters: [(String, String)] = []

    if let args = attr.arguments?.as(LabeledExprListSyntax.self) {
        for arg in args {
            switch arg.label?.text {
            case "stackName":
                stackName = extractStringLiteral(arg.expression) ?? "test-stack"
            case "parameters":
                parameters = extractDictionaryLiteral(arg.expression)
            default:
                break
            }
        }
    }

    return LocalStackArgs(stackName: stackName, parameters: parameters)
}

// MARK: - Syntax Helpers

private func extractStringLiteral(_ expr: ExprSyntax) -> String? {
    if let stringLit = expr.as(StringLiteralExprSyntax.self) {
        return stringLit.segments.map { $0.trimmedDescription }.joined()
    }
    return nil
}

private func extractArrayLiteral(_ expr: ExprSyntax) -> [String] {
    guard let arrayExpr = expr.as(ArrayExprSyntax.self) else { return [] }
    return arrayExpr.elements.compactMap { element in
        element.expression.trimmedDescription
    }
}

private func extractDictionaryLiteral(_ expr: ExprSyntax) -> [(String, String)] {
    guard let dictExpr = expr.as(DictionaryExprSyntax.self) else { return [] }
    guard case let .elements(elements) = dictExpr.content else { return [] }
    return elements.compactMap { element in
        guard let key = extractStringLiteral(element.key),
            let value = extractStringLiteral(element.value)
        else { return nil }
        return (key, value)
    }
}

// MARK: - Code Generation

private func generateSpec(for prop: ContainerProperty) -> String {
    switch prop.kind {
    case .container(let args):
        var configParts: [String] = ["image: \"\(args.image)\""]

        if !args.ports.isEmpty {
            let portMappings = args.ports.map { "PortMapping(containerPort: \($0))" }.joined(separator: ", ")
            configParts.append("ports: [\(portMappings)]")
        }

        if !args.environment.isEmpty {
            let envPairs = args.environment.map { "\"\($0.0)\": \"\($0.1)\"" }.joined(separator: ", ")
            configParts.append("environment: [\(envPairs)]")
        }

        if let wait = args.waitStrategy {
            configParts.append("waitStrategy: \(wait)")
        }

        return "ContainerSpec(ContainerConfiguration(\(configParts.joined(separator: ", "))))"

    case .localStack:
        // For LocalStack, the spec is built at runtime using the StackOutputs type info.
        // The macro generates a placeholder spec; _ContainerTraitImpl reads the type's metadata.
        guard let typeName = prop.typeAnnotation else {
            let image = "localstack/localstack:latest"
            let config =
                "ContainerConfiguration(image: \"\(image)\", ports: [PortMapping(containerPort: 4566)], waitStrategy: .log(\"Ready.\"))"
            return "ContainerSpec(\(config))"
        }
        return """
            ContainerSpec(LocalStackContainer(services: \(typeName).requiredServices).configuration())
            """
    }
}

private func generateTraitImpl(properties: [ContainerProperty]) -> [DeclSyntax] {
    let fragments = properties.map { generatePropertyFragments(for: $0) }

    let keyStartLines = fragments.flatMap(\.startLines).joined(separator: "\n")
    let waitLines = fragments.flatMap(\.waitLines).joined(separator: "\n")
    let setupLines = fragments.flatMap(\.setupLines).joined(separator: "\n")
    let teardownLines = fragments.flatMap(\.teardownLines).joined(separator: "\n")

    let contextDictEntries = fragments.map(\.contextEntry).joined(separator: ",\n                    ")
    let outputEntries = fragments.compactMap(\.outputEntry)
    let outputDictEntries = outputEntries.isEmpty ? ":" : outputEntries.joined(separator: ",\n                    ")

    let provideScope = buildProvideScopeBody(
        keyStartLines: keyStartLines,
        waitLines: waitLines,
        setupLines: setupLines,
        contextDictEntries: contextDictEntries,
        outputDictEntries: outputDictEntries,
        teardownLines: teardownLines
    )

    return [DeclSyntax(stringLiteral: provideScope)]
}

private struct PropertyFragments {
    var startLines: [String]
    var waitLines: [String]
    var setupLines: [String]
    var contextEntry: String
    var outputEntry: String?
    var teardownLines: [String]
}

private func generatePropertyFragments(for prop: ContainerProperty) -> PropertyFragments {
    let keyName = "_\(capitalizeFirst(prop.name))Key"

    let startLines = [
        """
                let \(prop.name)Spec = \(keyName).spec
                logger.info("Starting container", metadata: ["image": "\\(\(prop.name)Spec.configuration.image)"])
                try await runtime.pullImage(\(prop.name)Spec.configuration.image)
                let \(prop.name)Container = try await runtime.startContainer(from: \(prop.name)Spec.configuration)
        """
    ]

    let waitLines = [
        """
                try await WaitStrategyExecutor.waitUntilReady(
                    container: \(prop.name)Container,
                    configuration: \(prop.name)Spec.configuration,
                    runtime: runtime
                )
        """
    ]

    var setupLines = [
        """
                for setup in \(prop.name)Spec.setups {
                    try await setup.setUp(container: \(prop.name)Container)
                }
        """
    ]

    var outputEntry: String?
    if case .localStack(let args) = prop.kind, let typeName = prop.typeAnnotation {
        setupLines.append(
            """
                    let \(prop.name)Endpoint = try LocalStackEndpoint(container: \(prop.name)Container).awsEndpoint()
                    let \(prop.name)Fetcher = CloudFormationSetup(templatePath: "", stackName: \"\(args.stackName)\")
                    let \(prop.name)RawOutputs = try await \(prop.name)Fetcher.fetchOutputs(endpoint: \(prop.name)Endpoint)
            """
        )
        outputEntry = "ObjectIdentifier(\(keyName).self): \(prop.name)RawOutputs"
        _ = typeName
    }

    let teardownLines = [
        """
                for setup in \(prop.name)Spec.setups {
                    try? await setup.tearDown(container: \(prop.name)Container)
                }
                do {
                    try await runtime.stopContainer(\(prop.name)Container)
                    try await runtime.removeContainer(\(prop.name)Container)
                } catch {
                    logger.warning("Failed to clean up container", metadata: ["id": "\\(\(prop.name)Container.id)", "error": "\\(error)"])
                }
        """
    ]

    return PropertyFragments(
        startLines: startLines,
        waitLines: waitLines,
        setupLines: setupLines,
        contextEntry: "ObjectIdentifier(\(keyName).self): \(prop.name)Container",
        outputEntry: outputEntry,
        teardownLines: teardownLines
    )
}

private func buildProvideScopeBody(
    keyStartLines: String,
    waitLines: String,
    setupLines: String,
    contextDictEntries: String,
    outputDictEntries: String,
    teardownLines: String
) -> String {
    """
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

    \(keyStartLines)
    \(waitLines)
    \(setupLines)

            let context = ContainerTestContext(
                containers: [
                    \(contextDictEntries)
                ],
                stackOutputs: [\(outputDictEntries)]
            )
            do {
                try await ContainerTestContext.$current.withValue(context) {
                    try await execute()
                }
            } catch {
                logger.error("Container lifecycle error", metadata: ["error": "\\(error)"])
                throw error
            }

    \(teardownLines)
        }
    }
    """
}

private func capitalizeFirst(_ string: String) -> String {
    guard let first = string.first else { return string }
    return String(first).uppercased() + string.dropFirst()
}

// MARK: - Error Type

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
