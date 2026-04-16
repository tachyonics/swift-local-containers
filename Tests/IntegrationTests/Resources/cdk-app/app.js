const path = require('path');
const cdk = require('aws-cdk-lib');
const { Stack } = require('aws-cdk-lib');
const s3 = require('aws-cdk-lib/aws-s3');
const s3_assets = require('aws-cdk-lib/aws-s3-assets');

// Assetless stack — used by the declarative `cdkapps[]` path and by the
// imperative `CDKSetup(autoBootstrap: false)` path. Contains only "inline"
// resources that don't require a staging bucket, so `CloudFormationSetup`'s
// SSM bootstrap-version stub is sufficient to deploy it against LocalStack.
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

// Asset-bearing stack — used by the imperative `CDKSetup(autoBootstrap: true)`
// path, which delegates to `cdklocal` to bootstrap a real CDKToolkit stack
// in LocalStack and deploy with asset upload. Uses `s3_assets.Asset` to
// create a genuine file asset (asset.txt) that CDK uploads to the staging
// bucket during deploy — exercising the exact pipeline the autoBootstrap
// path exists to support. Deliberately avoids Lambda/ECS/etc. because
// LocalStack needs Docker socket access to create those resources, which
// requires volume mount support the framework doesn't yet expose. The
// asset-upload pipeline itself is fully exercised without any such
// runtime resource.
class AssetStack extends Stack {
  constructor(scope, id, props) {
    super(scope, id, props);

    const asset = new s3_assets.Asset(this, 'Asset', {
      path: path.join(__dirname, 'asset.txt'),
    });

    new cdk.CfnOutput(this, 'AssetBucket', {
      value: asset.s3BucketName,
    });
    new cdk.CfnOutput(this, 'AssetKey', {
      value: asset.s3ObjectKey,
    });
  }
}

// Uses CDK's DefaultStackSynthesizer — the same configuration a production
// app would use. `CDKSetup` stubs the `/cdk-bootstrap/hnb659fds/version` SSM
// parameter in LocalStack (for the assetless path), or delegates to
// `cdklocal bootstrap` (for the asset-bearing path), so the synthesized
// templates deploy cleanly without any prior manual bootstrap step.
const app = new cdk.App();
new TestStack(app, 'CdkIntegrationTestStack');
new AssetStack(app, 'CdkAssetIntegrationTestStack');
