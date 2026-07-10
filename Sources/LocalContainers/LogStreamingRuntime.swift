import Logging

/// Optional capability for a `ContainerRuntime` that can stream a running
/// container's stdout+stderr to a logger.
///
/// Runtimes implement this when they have efficient access to a follow-style
/// log stream from the underlying daemon. The trait detects this conformance
/// via downcast — runtimes that don't conform simply skip streaming for
/// containers that request it.
public protocol LogStreamingRuntime: ContainerRuntime {
    /// Stream `container`'s stdout+stderr to a logger at `level`, with
    /// `container=<name>` metadata on each line.
    ///
    /// Returns when the underlying stream closes (e.g. the container exits
    /// and the daemon hangs up) or when the surrounding `Task` is cancelled.
    /// Errors are swallowed — streaming is observability, not correctness.
    func streamLogs(
        container: RunningContainer,
        level: Logger.Level
    ) async
}
