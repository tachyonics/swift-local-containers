import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private struct ContainerMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity = .error

    static let environmentRequiresNamedType = ContainerMacroDiagnostic(
        message:
            "@DockerfileContainer with `environment:` requires the enclosing "
            + "@Containers declaration to be a named type "
            + "(struct, enum, class, or actor).",
        diagnosticID: MessageID(
            domain: "ContainerMacros",
            id: "environmentRequiresNamedType"
        )
    )
}

/// Member macro that scans properties for `@Container` / `@LocalStackContainer`
/// attributes and generates `ContainerKey` enums and a `containerTrait` property.
public struct ContainerDeclarationsMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let annotatedProperties = collectAnnotatedProperties(from: declaration)

        guard !annotatedProperties.isEmpty else {
            return []
        }

        let typeName = enclosingTypeName(of: declaration)

        // The dockerfile-with-environment path emits code referencing the
        // enclosing struct by name; if `@Containers` is attached to a decl
        // we can't name (a protocol or extension), bail with a clear
        // diagnostic instead of generating broken expanded code.
        let needsNamedType = annotatedProperties.contains { property in
            if case .dockerfile(_, _, _, .some) = property.kind { return true }
            return false
        }
        if needsNamedType, typeName == nil {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: ContainerMacroDiagnostic.environmentRequiresNamedType
                )
            ])
        }

        var declarations: [DeclSyntax] = []

        // Generate ContainerKey enum for each annotated property
        for property in annotatedProperties {
            let keyDecl = try generateKeyDeclaration(
                for: property,
                enclosingTypeName: typeName ?? ""
            )
            declarations.append(keyDecl)
        }

        // Generate containerTrait static property
        let traitDecl = generateContainerTrait(for: annotatedProperties)
        declarations.append(traitDecl)

        return declarations
    }

    private static func enclosingTypeName(
        of declaration: some DeclGroupSyntax
    ) -> String? {
        if let structDecl = declaration.as(StructDeclSyntax.self) { return structDecl.name.text }
        if let enumDecl = declaration.as(EnumDeclSyntax.self) { return enumDecl.name.text }
        if let classDecl = declaration.as(ClassDeclSyntax.self) { return classDecl.name.text }
        if let actorDecl = declaration.as(ActorDeclSyntax.self) { return actorDecl.name.text }
        return nil
    }

    // MARK: - Property Collection

    private static func collectAnnotatedProperties(
        from declaration: some DeclGroupSyntax
    ) -> [AnnotatedProperty] {
        var properties: [AnnotatedProperty] = []

        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                let binding = varDecl.bindings.first,
                let identifier = binding.pattern
                    .as(IdentifierPatternSyntax.self)?.identifier.text
            else {
                continue
            }

            let typeAnnotation = binding.typeAnnotation?.type

            for attribute in varDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self),
                    let attrName = attr.attributeName
                        .as(IdentifierTypeSyntax.self)?.name.text
                else {
                    continue
                }

                if attrName == "Container" {
                    let parsed = parseContainerAttribute(attr)
                    properties.append(
                        AnnotatedProperty(
                            name: identifier,
                            typeName: typeAnnotation,
                            kind: .container(
                                image: parsed.image,
                                ports: parsed.ports
                            )
                        )
                    )
                } else if attrName == "LocalStackContainer" {
                    let stackName = parseLocalStackAttribute(attr)
                    properties.append(
                        AnnotatedProperty(
                            name: identifier,
                            typeName: typeAnnotation,
                            kind: .localStack(stackName: stackName)
                        )
                    )
                } else if attrName == "DockerfileContainer" {
                    let parsed = parseDockerfileAttribute(attr)
                    properties.append(
                        AnnotatedProperty(
                            name: identifier,
                            typeName: typeAnnotation,
                            kind: .dockerfile(
                                context: parsed.context,
                                dockerfile: parsed.dockerfile,
                                waitStrategy: parsed.waitStrategy,
                                environment: parsed.environment
                            )
                        )
                    )
                }
            }
        }

        return properties
    }

    // MARK: - Attribute Parsing

    private static func parseContainerAttribute(
        _ attr: AttributeSyntax
    ) -> (image: String, ports: [String]) {
        var image = ""
        var ports: [String] = []

        guard
            let arguments = attr.arguments?
                .as(LabeledExprListSyntax.self)
        else {
            return (image, ports)
        }

        for arg in arguments {
            let label = arg.label?.text
            if label == "image" {
                if let stringLiteral = arg.expression
                    .as(StringLiteralExprSyntax.self)
                {
                    image = stringLiteral.segments.description
                }
            } else if label == "ports" {
                if let arrayExpr = arg.expression
                    .as(ArrayExprSyntax.self)
                {
                    for element in arrayExpr.elements {
                        ports.append(element.expression.description)
                    }
                }
            }
        }

        return (image, ports)
    }

    private static func parseLocalStackAttribute(
        _ attr: AttributeSyntax
    ) -> String {
        guard
            let arguments = attr.arguments?
                .as(LabeledExprListSyntax.self)
        else {
            return "test-stack"
        }

        for arg in arguments {
            if arg.label?.text == "stackName",
                let stringLiteral = arg.expression
                    .as(StringLiteralExprSyntax.self)
            {
                return stringLiteral.segments.description
            }
        }

        return "test-stack"
    }

    struct ParsedDockerfileAttribute {
        var context: String = "."
        var dockerfile: String = "Dockerfile"
        var waitStrategy: String = ".port"
        var environment: String?
    }

    private static func parseDockerfileAttribute(
        _ attr: AttributeSyntax
    ) -> ParsedDockerfileAttribute {
        var parsed = ParsedDockerfileAttribute()

        guard
            let arguments = attr.arguments?
                .as(LabeledExprListSyntax.self)
        else {
            return parsed
        }

        for arg in arguments {
            let label = arg.label?.text
            if label == "context",
                let stringLiteral = arg.expression
                    .as(StringLiteralExprSyntax.self)
            {
                parsed.context = stringLiteral.segments.description
            } else if label == "dockerfile",
                let stringLiteral = arg.expression
                    .as(StringLiteralExprSyntax.self)
            {
                parsed.dockerfile = stringLiteral.segments.description
            } else if label == "waitStrategy" {
                // Pass the expression through verbatim — it's a WaitStrategy enum
                // value (e.g. `.port`, `.httpGet(path: "/health")`).
                parsed.waitStrategy = arg.expression.description
            } else if label == "environment" {
                // Pass the expression through verbatim — closure or key path of
                // type `(Outer) -> [String: String]`. Splatted into a typed
                // static let so the enclosing struct's name resolves naturally.
                parsed.environment = arg.expression.description
            }
        }

        return parsed
    }

    // MARK: - Code Generation

    private static func generateKeyDeclaration(
        for property: AnnotatedProperty,
        enclosingTypeName: String
    ) throws -> DeclSyntax {
        let keyName = "_\(property.name.capitalizedFirst)Key"

        switch property.kind {
        case .container(let image, let ports):
            let portMappings = ports.map {
                "PortMapping(containerPort: \($0))"
            }.joined(separator: ", ")

            return """
                private enum \(raw: keyName): ContainerKey {
                    static let spec = ContainerSpec(
                        ContainerConfiguration(
                            image: \(literal: image),
                            ports: [\(raw: portMappings)]
                        )
                    )
                }
                """

        case .localStack(let stackName):
            guard let typeName = property.typeName else {
                return ""
            }
            return """
                private enum \(raw: keyName): ContainerKey {
                    static let spec = ContainerSpec(
                        LocalStackContainer(
                            services: \(typeName).requiredServices,
                            environment: LocalStackContainer.environmentForwarding(
                                overriding: LocalContainersConfig.values
                            )
                        ).configuration(),
                        setups: [
                            CloudFormationSetup(
                                templatePath: \(typeName).templatePath,
                                stackName: \(literal: stackName)
                            ),
                        ]
                    )
                }
                """

        case .dockerfile(let context, let dockerfile, let waitStrategy, let environment):
            return generateDockerfileKey(
                keyName: keyName,
                propertyName: property.name,
                context: context,
                dockerfile: dockerfile,
                waitStrategy: waitStrategy,
                environment: environment,
                enclosingTypeName: enclosingTypeName
            )
        }
    }

    private static func generateDockerfileKey(
        keyName: String,
        propertyName: String,
        context: String,
        dockerfile: String,
        waitStrategy: String,
        environment: String?,
        enclosingTypeName: String
    ) -> DeclSyntax {
        let tag = "local-containers/\(propertyName.lowercased()):test"

        // No env provider: simple ContainerSpec with only configuration.
        guard let environment else {
            return """
                private enum \(raw: keyName): ContainerKey {
                    static let spec = ContainerSpec(
                        ContainerConfiguration(
                            image: .build(
                                BuildSpec.resolvedAgainstPackage(
                                    contextPath: \(literal: context),
                                    from: #filePath,
                                    dockerfile: \(literal: dockerfile),
                                    tag: \(literal: tag)
                                )
                            ),
                            waitStrategy: \(raw: waitStrategy)
                        )
                    )
                }
                """
        }

        // With env provider: typed static let splats the user's expression at
        // a known type so KeyPath/closure expressions resolve against the
        // enclosing @Containers struct. The wrapper closure on the spec
        // constructs an instance and invokes the typed provider — the trait
        // sets up a partial ContainerTestContext before calling it.
        return """
            private enum \(raw: keyName): ContainerKey {
                static let _envProvider:
                    @Sendable (\(raw: enclosingTypeName)) -> [String: String] =
                    \(raw: environment)

                static let spec = ContainerSpec(
                    ContainerConfiguration(
                        image: .build(
                            BuildSpec.resolvedAgainstPackage(
                                contextPath: \(literal: context),
                                from: #filePath,
                                dockerfile: \(literal: dockerfile),
                                tag: \(literal: tag)
                            )
                        ),
                        waitStrategy: \(raw: waitStrategy)
                    ),
                    environmentProvider: { _envProvider(\(raw: enclosingTypeName)()) }
                )
            }
            """
    }

    private static func generateContainerTrait(
        for properties: [AnnotatedProperty]
    ) -> DeclSyntax {
        let keyEntries = properties.map { property in
            let keyName = "_\(property.name.capitalizedFirst)Key"
            switch property.kind {
            case .container, .dockerfile:
                return "ErasedContainerKey(\(keyName).self)"
            case .localStack:
                guard let typeName = property.typeName else {
                    return "ErasedContainerKey(\(keyName).self)"
                }
                return """
                    ErasedContainerKey(\(keyName).self, \
                    outputConstructor: { try \(typeName)(rawOutputs: $0) })
                    """
            }
        }.joined(separator: ", ")

        return """
            static let containerTrait = ContainerTrait(
                keys: [\(raw: keyEntries)],
                runtime: PlatformRuntime()
            )
            """
    }
}

// MARK: - ExtensionMacro

extension ContainerDeclarationsMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let annotatedProperties = collectAnnotatedProperties(from: declaration)
        guard !annotatedProperties.isEmpty else {
            return []
        }

        // If the member-macro path will fail (env supplied but enclosing decl
        // can't be named), don't emit the conformance extension either — its
        // member-macro counterpart's diagnostic is the user-visible error;
        // emitting a half-finished conformance just adds confusing follow-on
        // compile errors.
        let needsNamedType = annotatedProperties.contains { property in
            if case .dockerfile(_, _, _, .some) = property.kind { return true }
            return false
        }
        if needsNamedType, enclosingTypeName(of: declaration) == nil {
            return []
        }

        // `Sendable` is required so a `@Sendable` environmentProvider closure
        // (emitted by `@DockerfileContainer(environment:)`) can construct an
        // instance of the enclosing struct to read sibling outputs through the
        // macro-generated computed properties. For the typical @Containers
        // struct (only computed properties reading @TaskLocal), conformance
        // is auto-synthesized.
        let extensionDecl: DeclSyntax = """
            extension \(type.trimmed): ContainerDeclarations, Sendable {}
            """

        guard let extensionSyntax = extensionDecl.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [extensionSyntax]
    }
}

// MARK: - Supporting Types

struct AnnotatedProperty {
    let name: String
    let typeName: TypeSyntax?
    let kind: Kind

    enum Kind {
        case container(image: String, ports: [String])
        case localStack(stackName: String)
        case dockerfile(
            context: String,
            dockerfile: String,
            waitStrategy: String,
            environment: String?
        )
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}
