import Testing

extension Tag {
    /// Tag for integration tests that require a container runtime.
    @Tag public static var integration: Self

    /// Tag for tests that require Docker/Podman.
    @Tag public static var docker: Self

    /// Tag for tests that require LocalStack.
    @Tag public static var localstack: Self
}
