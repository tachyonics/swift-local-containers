import AsyncHTTPClient
import Foundation
import LocalContainers
import Logging
import NIOCore

/// Stubs the `/cdk-bootstrap/hnb659fds/version` SSM parameter in LocalStack
/// to satisfy CDK's `DefaultStackSynthesizer` `CheckBootstrapVersion` rule
/// without requiring a real `cdk bootstrap` stack to have been deployed.
///
/// CDK's default synthesizer bakes a `BootstrapVersion` parameter into every
/// template it emits, whose default value resolves an SSM parameter created
/// by `cdk bootstrap`. LocalStack can't resolve that parameter without a real
/// bootstrap, so `CreateStack` fails with "Parameter BootstrapVersion should
/// either have input value or default value." We work around this by putting
/// a compatible version number into SSM ourselves before deploying — the
/// synthesized template then resolves the default cleanly and the
/// `CheckBootstrapVersion` rule passes.
///
/// Shared between ``CloudFormationSetup`` (which runs the stub automatically
/// when it detects the CDK bootstrap marker in a template body) and
/// ``CDKSetup`` (which runs it explicitly in the `autoBootstrap: false`
/// path).
internal enum BootstrapVersionStub {
    /// The SSM parameter CDK's default synthesizer references in every
    /// template it emits.
    static let ssmParameterName = "/cdk-bootstrap/hnb659fds/version"

    /// Returns `true` if the CF template body contains a reference to the
    /// CDK bootstrap version SSM parameter. Used by `CloudFormationSetup`
    /// to decide whether to run the stub automatically.
    static func templateNeedsStub(_ templateBody: String) -> Bool {
        templateBody.contains(ssmParameterName)
    }

    /// PUTs the SSM parameter against a LocalStack gateway endpoint. Uses
    /// value `"20"`, which is safely above CDK's `CheckBootstrapVersion`
    /// rule's rejected range (v1–v5) and high enough not to confuse any
    /// real bootstrap value it might be overwriting.
    static func stub(endpoint: String, logger: Logger) async throws {
        logger.info(
            "Stubbing CDK bootstrap version SSM parameter",
            metadata: ["parameter": "\(ssmParameterName)"]
        )

        let body = #"""
            {"Name":"\#(ssmParameterName)","Value":"20","Type":"String","Overwrite":true}
            """#

        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        request.headers.add(
            name: "Content-Type",
            value: "application/x-amz-json-1.1"
        )
        request.headers.add(
            name: "X-Amz-Target",
            value: "AmazonSSM.PutParameter"
        )
        // LocalStack doesn't verify SigV4 signatures; a well-formed dummy
        // header is sufficient to route the request.
        request.headers.add(
            name: "Authorization",
            value:
                "AWS4-HMAC-SHA256 Credential=test/20220101/us-east-1/ssm/aws4_request, SignedHeaders=host, Signature=test"
        )
        request.body = .bytes(Data(body.utf8))

        let response = try await HTTPClient.shared.execute(
            request,
            timeout: .seconds(10)
        )
        let responseBody = try await response.body.collect(upTo: 1024 * 1024)
        let responseText = String(buffer: responseBody)

        guard (200..<300).contains(response.status.code) else {
            throw ContainerError.setupFailed(
                step: "BootstrapVersionStub",
                reason:
                    "Failed to stub bootstrap version SSM parameter: HTTP \(response.status.code): \(responseText)"
            )
        }
    }
}
