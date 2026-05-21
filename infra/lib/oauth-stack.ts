import * as cdk from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as nodejs from "aws-cdk-lib/aws-lambda-nodejs";
import * as apigateway from "aws-cdk-lib/aws-apigateway";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as events from "aws-cdk-lib/aws-events";
import * as targets from "aws-cdk-lib/aws-events-targets";
import * as iam from "aws-cdk-lib/aws-iam";
import * as ssm from "aws-cdk-lib/aws-ssm";
import { Construct } from "constructs";
import * as path from "path";

export interface OAuthStackProps extends cdk.StackProps {
  feishuAppId: string;
  feishuAppSecret: string;
}

export class OAuthStack extends cdk.Stack {
  public readonly oauthEndpoint: string;
  public readonly secretPrefix: string;
  public readonly appSecretId: string;

  constructor(scope: Construct, id: string, props: OAuthStackProps) {
    super(scope, id, props);

    this.secretPrefix = "lark-mcp/users";
    this.appSecretId = "lark-mcp/feishu-app";

    const appSecret = new secretsmanager.Secret(this, "FeishuAppSecret", {
      secretName: this.appSecretId,
      secretStringValue: cdk.SecretValue.unsafePlainText(
        JSON.stringify({ appId: props.feishuAppId, appSecret: props.feishuAppSecret })
      ),
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Stable state secret: create SSM param only if not exists (CDK handles this)
    const stateSecretParam = new ssm.StringParameter(this, "StateSecret", {
      parameterName: "/lark-mcp/state-secret",
      stringValue: require("crypto").randomBytes(32).toString("hex"),
      description: "HMAC secret for OAuth state",
    });

    const oauthFn = new nodejs.NodejsFunction(this, "OAuthFunction", {
      runtime: lambda.Runtime.NODEJS_20_X,
      entry: path.join(__dirname, "../../lambda/token-refresh-shim/index.ts"),
      handler: "handler",
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        CALLBACK_URL: "PLACEHOLDER",
        SECRET_PREFIX: this.secretPrefix,
        APP_SECRET_ID: this.appSecretId,
        STATE_SECRET: stateSecretParam.stringValue,
      },
      bundling: { externalModules: ["@aws-sdk/*"], minify: true, target: "node20" },
    });

    appSecret.grantRead(oauthFn);
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:CreateSecret", "secretsmanager:ListSecrets", "secretsmanager:DescribeSecret"],
      resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:${this.secretPrefix}/*`],
    }));
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:ListSecrets"],
      resources: ["*"],
    }));

    // API Gateway: only /authorize and /callback (NO /token - not public)
    const api = new apigateway.RestApi(this, "OAuthApi", { restApiName: "lark-mcp-oauth" });
    const integration = new apigateway.LambdaIntegration(oauthFn);
    api.root.addResource("authorize").addMethod("GET", integration);
    api.root.addResource("callback").addMethod("GET", integration);

    // CloudFront
    const distribution = new cloudfront.Distribution(this, "OAuthCF", {
      defaultBehavior: {
        origin: new origins.RestApiOrigin(api),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
    });

    this.oauthEndpoint = `https://${distribution.distributionDomainName}`;

    const cfnFn = oauthFn.node.defaultChild as lambda.CfnFunction;
    cfnFn.addPropertyOverride("Environment.Variables.CALLBACK_URL", `${this.oauthEndpoint}/callback`);

    new events.Rule(this, "TokenRefreshRule", {
      schedule: events.Schedule.rate(cdk.Duration.hours(1)),
      targets: [new targets.LambdaFunction(oauthFn)],
    });

    new cdk.CfnOutput(this, "OAuthEndpoint", { value: this.oauthEndpoint });
    new cdk.CfnOutput(this, "FeishuRedirectUrl", {
      value: `${this.oauthEndpoint}/callback`,
      description: "Add this to Feishu app redirect URLs",
    });
  }
}
