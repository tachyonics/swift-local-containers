import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@LocalStackContainer` — Transforms a stored property into a computed getter
/// that retrieves the raw stack outputs from `ContainerTestContext` and constructs
/// the typed `StackOutputs` value.
public struct LocalStackContainerMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            throw MacroError("@LocalStackContainer can only be applied to a stored property")
        }

        let propName = pattern.identifier.text
        let keyName = "_\(capitalizeFirst(propName))Key"

        guard let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription else {
            throw MacroError("@LocalStackContainer property must have a type annotation")
        }

        // Parse stackName from the attribute arguments
        var stackName = "test-stack"
        if let args = node.arguments?.as(LabeledExprListSyntax.self) {
            for arg in args {
                if arg.label?.text == "stackName",
                    let stringLit = arg.expression.as(StringLiteralExprSyntax.self)
                {
                    stackName = stringLit.segments.map { $0.trimmedDescription }.joined()
                }
            }
        }

        let getter: AccessorDeclSyntax = """
            get throws {
                let ctx = try ContainerTestContext.requireCurrent()
                guard let rawOutputs = ctx.outputs(for: ObjectIdentifier(\(raw: keyName).self)) else {
                    throw StackOutputError.outputsNotAvailable(stackName: \(literal: stackName))
                }
                return try \(raw: typeAnnotation)(rawOutputs: rawOutputs)
            }
            """

        return [getter]
    }

    private static func capitalizeFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return String(first).uppercased() + string.dropFirst()
    }
}
