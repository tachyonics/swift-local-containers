import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ContainerMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ContainerDeclarationsMacro.self,
        ContainerMacro.self,
        LocalStackContainerMacro.self,
    ]
}
