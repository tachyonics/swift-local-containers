/// Errors related to CloudFormation stack output retrieval and validation.
public enum StackOutputError: Error, Sendable {
    /// An expected output key was not found in the stack outputs.
    case missingOutput(key: String, availableKeys: [String])

    /// Stack outputs could not be retrieved (e.g. stack not yet deployed).
    case outputsNotAvailable(stackName: String)
}
