import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ContainerMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ContainerSuiteMacro.self,
        ContainerMacro.self,
        LocalStackContainerMacro.self,
    ]
}
