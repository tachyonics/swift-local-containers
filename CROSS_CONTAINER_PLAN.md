# Cross-Container Env Injection — Design Plan

This document captures the design for the **Cross-container env injection** sub-item of milestone 4 in `TODO.md`. The build/run primitive shipped in 0.7.x; this is the next piece — wiring environment from a sibling container's outputs into a `@DockerfileContainer` service container.

## Motivating use case

A typical web service depends on infrastructure (DDB tables, SQS queues, SNS topics, Step Functions, etc.) that's deployed via CloudFormation/CDK. In production, the service's runtime container reads the names/URIs of those resources from environment variables, set on the ECS task definition by referencing the dependency stack's outputs.

For tests, we want to:

1. Deploy the dependency stack to a `@LocalStackContainer`.
2. Build the service from its Dockerfile via `@DockerfileContainer`.
3. Wire the service's environment from the LocalStack stack's outputs — same env keys, same source values as production — so the service-under-test sees a runtime indistinguishable from prod (modulo the LocalStack endpoint).

Concrete example for `secondary/task-cluster`:

```swift
@Containers
struct TaskClusterContainers {
    @LocalStackContainer(stackName: "task-cluster-test")
    var aws: TaskClusterStackOutputs   // produces `taskTableName`, `awsEndpoint`, etc.

    @DockerfileContainer(
        environment: \.aws.applicationEnvironment,
        waitStrategy: .httpGet(path: "/health")
    )
    var taskCluster: ServiceEndpoint
}
```

The TaskCluster service reads `TASK_TABLE_NAME` and `AWS_ENDPOINT_URL` from its environment, hits LocalStack DDB instead of the in-memory table, and the integration test exercises the full stack.

## The contract has two parts

The wiring between Stack 1 (dependency) and the service has two pieces:

| Part | Source of truth | Status |
|------|----------------|--------|
| **Schema of outputs** (`taskTableName`, `awsEndpoint`, etc.) | Stack 1's CloudFormation/CDK template, surfaced via `cdkapps[]` codegen as `TaskClusterStackOutputs`. | Already shared between test and prod — no drift risk. |
| **Mapping from outputs → env vars** (`"TASK_TABLE_NAME": taskTableName`) | Today: written twice — in Stack 2's CDK code (`taskDef.addEnvironment(...)`) and in the test fixture. | This is what we're solving. |

This plan addresses the second part **at the test side only**. A separate follow-up (see "Future: Stack 2 contract codegen" below) can produce a generated `applicationEnvironment` property that both sides consume, eliminating the duplication entirely. The closure API works identically with or without that codegen — the codegen is purely additive.

## API

The `@DockerfileContainer` macro gains an `environment:` argument. The user supplies any expression that resolves to `(Outer) -> [String: String]` where `Outer` is the enclosing `@Containers` struct.

### Forms the user can write

**Pure contract — uses the (future) codegen'd contract verbatim:**
```swift
@DockerfileContainer(
    environment: \.aws.applicationEnvironment,
    waitStrategy: .httpGet(path: "/health")
)
var taskCluster: ServiceEndpoint
```

**Contract + overrides** (test-only env vars like `AWS_ENDPOINT_URL` pointing at LocalStack):
```swift
@DockerfileContainer(
    environment: { c in
        c.aws.applicationEnvironment.merging([
            "AWS_ENDPOINT_URL": c.aws.awsEndpoint,
            "AWS_ACCESS_KEY_ID": "test",
            "AWS_SECRET_ACCESS_KEY": "test",
        ]) { _, new in new }
    },
    waitStrategy: .httpGet(path: "/health")
)
var taskCluster: ServiceEndpoint
```

**No contract / hand-written** — escape hatch when no Stack 2 codegen exists:
```swift
@DockerfileContainer(
    environment: { c in [
        "TASK_TABLE_NAME": c.aws.taskTableName,
        "AWS_ENDPOINT_URL": c.aws.awsEndpoint,
    ]},
    waitStrategy: .httpGet(path: "/health")
)
var taskCluster: ServiceEndpoint
```

**No env (default)** — `environment:` argument omitted; existing behaviour.

The key path form works because Swift (SE-0249) coerces `KeyPath<Root, Value>` to `(Root) -> Value` automatically. No special-casing in the macro.

## Mechanism

### `ContainerSpec` change

Non-generic. Gains a stored optional environment provider:

```swift
public struct ContainerSpec: Sendable {
    public let configuration: ContainerConfiguration
    public let setups: [any ContainerSetup]
    public let environmentProvider: (@Sendable () -> [String: String])?

    public init(
        _ configuration: ContainerConfiguration,
        setups: [any ContainerSetup] = [],
        environmentProvider: (@Sendable () -> [String: String])? = nil
    ) { ... }
}
```

The provider has signature `() -> [String: String]` — type-erased at the spec layer. The bridge from the user's typed `(Outer) -> [String: String]` to this uniform interface happens in the macro (see below).

### `ContainerConfiguration` change

New `with(environment:)` helper, mirroring the existing `with(ports:)`:

```swift
public func with(environment: [String: String]) -> ContainerConfiguration { ... }
```

The trait merges the provider's output over the static `configuration.environment` and calls `with(environment:)` to build the configuration that gets passed to `startContainer`.

### `@DockerfileContainer` macro signature

```swift
@attached(accessor)
public macro DockerfileContainer(
    context: String = ".",
    dockerfile: String = "Dockerfile",
    waitStrategy: WaitStrategy = .port,
    environment: (any Sendable)? = nil
) = #externalMacro(...)
```

The `(any Sendable)?` arg type is permissive enough to accept both closure and key path expressions, while still rejecting non-Sendable closures (those capturing non-Sendable state) at the call site with a clear Sendable-conformance error.

### `@Containers` macro emission

The member macro already scans per-property attributes. For `@DockerfileContainer` properties with an `environment:` arg, it generates two pieces of code in addition to the existing key enum:

```swift
// Typed binding — anchors type errors at this line if the user's expression
// is incompatible with the enclosing struct's shape.
private static let _taskClusterEnvProvider:
    @Sendable (TaskClusterContainers) -> [String: String] =
    \.aws.applicationEnvironment    // <- user's expression spliced in verbatim

private enum _TaskClusterKey: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(
            image: .build(BuildSpec.resolvedAgainstPackage(...)),
            waitStrategy: .httpGet(path: "/health")
        ),
        environmentProvider: {
            _taskClusterEnvProvider(TaskClusterContainers())
        }
    )
}
```

The wrapper closure (`environmentProvider`):
- Constructs an instance of the enclosing struct (`TaskClusterContainers()`).
- Calls the typed provider with that instance.
- Returns `[String: String]`.

The instance's macro-generated computed properties (`var aws: TaskClusterStackOutputs { get { ... } }`) read from `ContainerTestContext.$current` — which the trait sets to a *partial* context (containers started so far) before invoking the provider.

### `@Containers` extension emission

The existing extension is extended to also conform to `Sendable`:

```swift
extension TaskClusterContainers: ContainerDeclarations, Sendable {}
```

The wrapper closure constructs `TaskClusterContainers()`; for that construction to be valid in a `@Sendable` closure, the struct must be Sendable. Typical `@Containers` structs have only computed properties reading from `@TaskLocal`, so synthesized Sendable conformance is automatic.

### Trait orchestration

`ContainerTrait.provideScope` and `SharedContainerManager` both gain the same flow change. Pseudocode:

```swift
var started: [ObjectIdentifier: RunningContainer] = [:]

for key in keys {                            // declaration order
    let spec = key.spec
    let partialContext = ContainerTestContext(containers: started, ...)

    // Evaluate the env provider against the partial context.
    let dynamicEnv = await ContainerTestContext.$current.withValue(partialContext) {
        spec.environmentProvider?() ?? [:]
    }

    let merged = spec.configuration.environment.merging(dynamicEnv) { _, new in new }
    let preparedConfig = try await prepareImage(
        for: spec.configuration.with(environment: merged),
        using: runtime,
        logger: logger
    )

    let container = try await runtime.startContainer(from: preparedConfig)
    try await WaitStrategyExecutor.waitUntilReady(...)
    // ... setup steps, store in `started`, etc.
}
```

The merge order is: dynamic provider wins over static `configuration.environment`. Override semantics — if the user sets `"FOO": "bar"` statically and the provider also produces `"FOO"`, the provider value is used.

## Decisions

The design space we explored, with the decision made and why.

### 1. Closure vs declarative dict for `environment:` arg

**Decision: closure (with key path coercion).**

Closure (or key path) form gives full Swift expression power: string interpolation, conditional injection, calling helper functions, merging with other dicts. A declarative dict like `["FOO": .from(\.aws.bar), "BAZ": .literal("qux")]` is more lint-friendly but adds API surface (`.from`, `.literal`, etc.) for marginal gain.

Key path form (`\.aws.applicationEnvironment`) handles the simplest case as cleanly as a declarative dict would.

### 2. Type erasure at the spec layer vs generic `ContainerSpec<Outer>`

**Decision: type-erase in `ContainerSpec` (Option 1).**

`ContainerSpec` stays non-generic. The macro emits a typed wrapper closure that bridges the user's typed provider to the uniform `() -> [String: String]` interface.

Rationale:
- The bridging is small and lives in the macro — same pattern as the existing `outputConstructor` in `ErasedContainerKey` (which captures a typed `(rawOutputs) throws -> Outputs` closure into an erased `(rawOutputs) throws -> Any`).
- A generic `ContainerSpec<Outer>` would propagate through `ContainerKey.associatedtype Outer`, `ErasedContainerKey`'s machinery, and the trait's `keys: [ErasedContainerKey]` array. Significant plumbing for marginal gain.
- Error UX: type errors anchor at the macro-emitted `_<prop>EnvProvider` typed let, which Xcode shows on right-click → Expand Macro. Slightly more steps to find than at the call site, but the error message itself is precise.

### 3. Declaration-order startup vs dependency-graph startup

**Decision: declaration order.**

Containers start in the order their properties appear in the `@Containers` struct. Users place dependencies first.

Rationale:
- A third the work — no graph construction, no topological sort, no syntactic analysis of closure bodies to infer deps.
- Predictable; matches user mental model of source-order semantics.
- Wrong-order is detectable and surfaces clearly: the macro-generated computed property `containers.aws` traps via `preconditionFailure` if the partial context doesn't have `aws` yet, with a clear "no container context" message.
- Escalation path: if multi-dep ordering surfaces real foot-guns, we can layer dep-graph on top later (either via syntactic analysis of closure bodies or an explicit `dependsOn:` arg) without breaking declaration-order users.

### 4. Macro arg type for `environment:`

**Decision: `(any Sendable)? = nil`.**

Permissive enough to accept any expression (closures, key paths, computed values), restrictive enough to enforce Sendable at the call site.

Alternatives considered:
- `Any?` — also accepts everything, but loses Sendable enforcement.
- Generic macro `<Outer>` with `environment: @Sendable (Outer) -> [String: String]` — Swift can't infer `Outer` from a key path or unannotated closure at the macro call site (no enclosing-type context). Requires the user to annotate the closure parameter (`{ (c: TaskClusterContainers) in ... }`) — boilerplate.
- Method-by-convention (separate `static let <prop>Environment` on the struct) — splits the wiring across two declarations. Worse ergonomics.

### 5. `@Containers` struct must be Sendable

**Decision: synthesize via the macro-generated extension.**

The wrapper closure constructs `TaskClusterContainers()` inside a `@Sendable` context, which requires the struct to be Sendable. The macro adds `Sendable` to the conformance list:

```swift
extension TaskClusterContainers: ContainerDeclarations, Sendable {}
```

For the typical `@Containers` struct (only computed properties reading `@TaskLocal`), this is automatically valid. If the user adds non-Sendable stored properties, they'll get a Sendable conformance error pointing at the extension — clear failure mode.

### 6. Wrong-order failure mode

**Decision: rely on the existing `preconditionFailure` in macro-generated property accessors.**

If a provider closure references a sibling that hasn't started yet (because the user ordered properties wrong), the partial context won't contain that sibling, and the macro-generated `var aws { get { ... } }` traps with the existing "No container context" message.

We could detect this at macro-expansion time via syntactic analysis of closure bodies, but that's speculative — wait for a real foot-gun before adding the machinery.

## Implementation plan

Steps, roughly in order. Each is a self-contained slice.

1. **`ContainerSpec` gains `environmentProvider`.** Add the field, add init defaults, no behavior change yet.
2. **`ContainerConfiguration.with(environment:)` helper.** Mirrors `with(ports:)`.
3. **Trait orchestration.** Update `ContainerTrait.provideScope` and `SharedContainerManager.container(...)` to evaluate `spec.environmentProvider` against a partial `ContainerTestContext` mid-startup, merge into config, then pass to `prepareImage`.
4. **`@DockerfileContainer` macro accepts `environment: (any Sendable)? = nil`.** Update declaration in `ContainerMacrosLib/Macros.swift`. Accessor macro itself doesn't change (it generates the property getter).
5. **`@Containers` member macro emission.** Recognize the `environment:` arg, emit the typed `_<prop>EnvProvider` static let plus the wrapper closure as the spec's `environmentProvider`. Update `parseDockerfileAttribute` to extract the env arg expression as syntax.
6. **`@Containers` Sendable conformance.** Add `Sendable` to the generated extension's conformance list.
7. **Tests.**
   - Unit: macro expansion test verifying the emitted code shape (key path form + closure form).
   - Unit: trait test using a mock runtime that verifies the partial context is set before `environmentProvider` is called and that env merging happens before `startContainer`.
   - Integration: task-cluster's second integration test — Stack 1 fixture in CDK (DDB table), TaskCluster service connects to LocalStack DDB via injected env, round-trip a task. (Forcing function — this is what proves the design.)

## Forcing function: task-cluster Stack 1

The implementation lands behind a real test backing TaskCluster on a real LocalStack DDB stack. Required:

- Add a CDK app under `secondary/task-cluster/cdk/` with a Stack 1 (the dependency stack: a single DDB table with appropriate keys).
- Add a `cdkapps[]` manifest entry to generate `TaskClusterStackOutputs` with `taskTableName` and any other relevant outputs.
- Update the integration test to use `@LocalStackContainer` for the dependency stack and inject env into TaskCluster.
- Update task-cluster's `TaskCluster.swift` (executable main) to honor `AWS_ENDPOINT_URL` and `TASK_TABLE_NAME` env vars when initializing the DynamoDB table — currently it uses the in-memory implementation unconditionally.

## Future: Stack 2 contract codegen

Optional follow-up that eliminates the remaining duplication between Stack 2's CDK env wiring and the test fixture's env wiring. **Not in scope for this milestone item.**

Sketch:
- Extend `cdkapps[]` (or add a new manifest entry like `applicationStacks[]`) to also synthesize Stack 2.
- Walk the synthesized template's `AWS::ECS::TaskDefinition.ContainerDefinitions[].Environment`, resolving cross-stack references (`Fn::ImportValue`, `Fn::GetAtt`) back to Stack 1 outputs.
- Emit a generated `applicationEnvironment` property as an extension on the StackOutputs type.
- Test consumes via `environment: \.aws.applicationEnvironment` — the closure API doesn't change.

This is purely additive; the closure API mechanism we're building now works whether or not codegen exists.

## Future: explicit dependency graph

If declaration-order startup proves error-prone in practice (a user reorders properties and tests fail at runtime with the wrong-order trap), we can add explicit dep declaration:

```swift
@DockerfileContainer(
    dependsOn: [\TaskClusterContainers.aws],
    environment: \.aws.applicationEnvironment,
    waitStrategy: .httpGet(path: "/health")
)
```

Or syntactic analysis of closure bodies to infer deps automatically. Both layer on top of the declaration-order default without breaking existing users. Wait for the foot-gun.
