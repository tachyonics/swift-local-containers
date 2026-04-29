/// Scope helpers used to communicate the current execution context from
/// the trait machinery down to value types like ``StackOutputs`` without
/// requiring those types to know about the trait module directly.
public enum ContainerExecutionScope: Sendable {
    /// True while a `@DockerfileContainer(environment:)` provider closure is
    /// being evaluated by the trait. Endpoint accessors that read this branch
    /// on its value to return container-relative URLs — reachable from the
    /// sibling container the env is being injected into — instead of
    /// host-relative URLs that the test runner uses for direct access.
    ///
    /// Set by `ContainerTestSupport`'s `resolveEnvironment` helper before
    /// invoking the user's `environment:` closure; reverts to `false` after
    /// the closure returns.
    @TaskLocal public static var isInSiblingEnvironmentResolution: Bool = false
}
