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
}
