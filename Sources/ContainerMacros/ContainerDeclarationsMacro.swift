import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

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

        var declarations: [DeclSyntax] = []

        // Generate ContainerKey enum for each annotated property
        for property in annotatedProperties {
            let keyDecl = try generateKeyDeclaration(for: property)
            declarations.append(keyDecl)
        }

        // Generate containerTrait static property
        let traitDecl = generateContainerTrait(for: annotatedProperties)
        declarations.append(traitDecl)

        return declarations
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

    // MARK: - Code Generation

    private static func generateKeyDeclaration(
        for property: AnnotatedProperty
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
        }
    }

    private static func generateContainerTrait(
        for properties: [AnnotatedProperty]
    ) -> DeclSyntax {
        let keyEntries = properties.map { property in
            let keyName = "_\(property.name.capitalizedFirst)Key"
            switch property.kind {
            case .container:
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

        let extensionDecl: DeclSyntax = """
            extension \(type.trimmed): ContainerDeclarations {}
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
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}
