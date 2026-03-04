import Testing

@testable import LocalStack

@Suite("CDKSetup")
struct CDKSetupTests {
    @Test("Default CDK command is npx cdk")
    func defaultCommand() {
        let setup = CDKSetup(cdkAppPath: "../infra", stackName: "MyStack")

        #expect(setup.cdkCommand == "npx cdk")
        #expect(setup.cdkAppPath == "../infra")
        #expect(setup.stackName == "MyStack")
        #expect(setup.autoBootstrap == true)
        #expect(setup.parameters.isEmpty)
    }

    @Test("Custom command is preserved")
    func customCommand() {
        let setup = CDKSetup(
            cdkAppPath: "../infra",
            stackName: "MyStack",
            cdkCommand: "cdk",
            autoBootstrap: false
        )

        #expect(setup.cdkCommand == "cdk")
        #expect(setup.autoBootstrap == false)
    }

    // MARK: - runShell

    @Test("Captures stdout from echo")
    func runShellCapturesStdout() async throws {
        let setup = CDKSetup(cdkAppPath: ".", stackName: "test")

        let output = try await setup.runShell("echo hello")

        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("Merges custom environment variables")
    func runShellMergesEnvironment() async throws {
        let setup = CDKSetup(cdkAppPath: ".", stackName: "test")

        let output = try await setup.runShell(
            "echo $MY_TEST_VAR",
            environment: ["MY_TEST_VAR": "custom_value"]
        )

        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "custom_value")
    }

    @Test("Throws on non-zero exit code with exit code in reason")
    func runShellThrowsOnFailure() async throws {
        let setup = CDKSetup(cdkAppPath: ".", stackName: "test")

        await #expect(throws: (any Error).self) {
            try await setup.runShell("exit 42")
        }
    }

    @Test("Inherits PATH from current process")
    func runShellInheritsPath() async throws {
        let setup = CDKSetup(cdkAppPath: ".", stackName: "test")

        let output = try await setup.runShell("which sh")

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
