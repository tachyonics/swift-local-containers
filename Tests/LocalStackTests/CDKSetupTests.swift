import Testing

@testable import LocalStack

@Suite("CDKSetup")
struct CDKSetupTests {
    @Test("Default CDK command is npx cdk, cdklocal command is npx cdklocal, autoBootstrap defaults off")
    func defaultCommand() {
        let setup = CDKSetup(cdkAppPath: "../infra", stackName: "MyStack")

        #expect(setup.cdkCommand == "npx cdk")
        #expect(setup.cdkLocalCommand == "npx cdklocal")
        #expect(setup.cdkAppPath == "../infra")
        #expect(setup.stackName == "MyStack")
        // Default is `false` — the SSM-stub fast path handles assetless
        // stacks (the primary use case) without the ~30s cdklocal bootstrap
        // penalty. Users opt in to `true` for asset-bearing stacks.
        #expect(setup.autoBootstrap == false)
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
