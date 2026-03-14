import SwiftSyntax
import SwiftSyntaxMacros

/// Accessor macro that generates a computed getter looking up
/// typed ``StackOutputs`` from `ContainerTestContext`.
public struct LocalStackContainerMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard
            let binding = declaration.as(VariableDeclSyntax.self)?
                .bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?
                .identifier.text
        else {
            return []
        }

        guard let typeAnnotation = binding.typeAnnotation?.type else {
            return []
        }

        let keyName = "_\(identifier.capitalizedFirst)Key"

        let getter: AccessorDeclSyntax = """
            get {
                guard let output: \(typeAnnotation) = ContainerTestContext.current?.output(
                    for: ObjectIdentifier(\(raw: keyName).self)
                ) else {
                    preconditionFailure(
                        "No container context — is this test inside a @Suite with containerTrait?"
                    )
                }
                return output
            }
            """

        return [getter]
    }
}
