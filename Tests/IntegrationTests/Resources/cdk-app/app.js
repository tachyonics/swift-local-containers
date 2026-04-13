const cdk = require('aws-cdk-lib');
const { Stack } = require('aws-cdk-lib');
const s3 = require('aws-cdk-lib/aws-s3');

class TestStack extends Stack {
  constructor(scope, id, props) {
    super(scope, id, props);

    const bucket = new s3.Bucket(this, 'TestBucket', {
      bucketName: 'cdk-integration-test-bucket',
    });

    new cdk.CfnOutput(this, 'BucketName', {
      value: bucket.bucketName,
    });
  }
}

// Uses CDK's DefaultStackSynthesizer — the same configuration a production
// app would use. `CDKSetup` stubs the `/cdk-bootstrap/hnb659fds/version` SSM
// parameter in LocalStack so the synthesized template deploys cleanly
// without a real `cdk bootstrap` ever having been run.
const app = new cdk.App();
new TestStack(app, 'CdkIntegrationTestStack');
