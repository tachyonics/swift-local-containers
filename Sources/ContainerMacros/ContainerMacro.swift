import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Container` — Transforms a stored property into a computed getter
/// that retrieves the `RunningContainer` from `ContainerTestContext`.
public struct ContainerMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            throw MacroError("@Container can only be applied to a stored property")
        }

        let propName = pattern.identifier.text
        let keyName = "_\(capitalizeFirst(propName))Key"

        let getter: AccessorDeclSyntax = """
            get throws {
                let ctx = try ContainerTestContext.requireCurrent()
                return try ctx.container(for: ObjectIdentifier(\(raw: keyName).self))
            }
            """

        return [getter]
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
