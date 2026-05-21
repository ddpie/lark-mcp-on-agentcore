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
import { Construct } from "constructs";
import * as path from "path";

export interface OAuthStackProps extends cdk.StackProps {
  feishuAppId: string;
  feishuAppSecret: string;
  runtimeArn?: string;
  customDomain?: string;
}

export class OAuthStack extends cdk.Stack {
  public readonly oauthEndpoint: string;
  public readonly secretPrefix: string;
  private readonly appSecretId: string;

  constructor(scope: Construct, id: string, props: OAuthStackProps) {
    super(scope, id, props);

    this.secretPrefix = "lark-mcp/users";
    this.appSecretId = "lark-mcp/feishu-app";

    // Import the secret by name — deploy.sh creates/updates it outside CDK
    // so that `cdk deploy` never overwrites the real credentials with placeholders.
    const appSecret = secretsmanager.Secret.fromSecretNameV2(
      this, "FeishuAppSecret", this.appSecretId
    );

    const oauthClientId = "lark-mcp";

    const oauthFn = new nodejs.NodejsFunction(this, "OAuthFunction", {
      runtime: lambda.Runtime.NODEJS_20_X,
      entry: path.join(__dirname, "../../lambda/token-refresh-shim/index.ts"),
      projectRoot: path.join(__dirname, "../.."),
      depsLockFilePath: path.join(__dirname, "../package-lock.json"),
      handler: "handler",
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        CALLBACK_URL: "SET_AFTER_DEPLOY",
        SECRET_PREFIX: this.secretPrefix,
        APP_SECRET_ID: this.appSecretId,
        STATE_SECRET: "SET_AFTER_DEPLOY",
        OAUTH_CLIENT_ID: oauthClientId,
        OAUTH_CLIENT_SECRET: "SET_AFTER_DEPLOY",
        ALLOWED_DOMAINS: props.customDomain || "",
      },
      bundling: { externalModules: ["@aws-sdk/*"], minify: true, target: "node20" },
    });

    appSecret.grantRead(oauthFn);
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:ListSecrets", "secretsmanager:DescribeSecret"],
      resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:lark-mcp/*`],
    }));
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:ListSecrets"],
      resources: ["*"],
    }));

    // Middleware Lambda (MCP proxy: token verify → SM → AgentCore)
    const middlewareFn = new nodejs.NodejsFunction(this, "MiddlewareFunction", {
      runtime: lambda.Runtime.NODEJS_20_X,
      entry: path.join(__dirname, "../../lambda/mcp-middleware/index.ts"),
      projectRoot: path.join(__dirname, "../.."),
      depsLockFilePath: path.join(__dirname, "../package-lock.json"),
      handler: "handler",
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      environment: {
        RUNTIME_ARN: props.runtimeArn || "",
        SECRET_PREFIX: this.secretPrefix,
        AUTHORIZE_BASE: "SET_AFTER_DEPLOY",
        DEPLOY_REGION: this.region,
      },
      bundling: { externalModules: ["@aws-sdk/*"], minify: true, target: "node20" },
    });
    middlewareFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:GetSecretValue"],
      resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:${this.secretPrefix}/*`],
    }));
    middlewareFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["ssm:GetParameter"],
      resources: [`arn:aws:ssm:${this.region}:${this.account}:parameter/lark-mcp/state-secret`],
    }));
    middlewareFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["bedrock-agentcore:InvokeAgentRuntime"],
      resources: [`arn:aws:bedrock-agentcore:${this.region}:${this.account}:runtime/*`],
    }));

    // Single API Gateway: all routes (OAuth + MCP)
    const api = new apigateway.RestApi(this, "OAuthApi", { restApiName: "lark-mcp-oauth" });
    const oauthIntegration = new apigateway.LambdaIntegration(oauthFn);
    const mcpIntegration = new apigateway.LambdaIntegration(middlewareFn);

    api.root.addResource("authorize").addMethod("GET", oauthIntegration);
    api.root.addResource("callback").addMethod("GET", oauthIntegration);
    api.root.addResource("token").addMethod("POST", oauthIntegration);
    const wellKnown = api.root.addResource(".well-known");
    wellKnown.addResource("oauth-authorization-server").addMethod("GET", oauthIntegration);

    const mcpResource = api.root.addResource("mcp");
    mcpResource.addMethod("POST", mcpIntegration);
    mcpResource.addMethod("GET", mcpIntegration);
    mcpResource.addMethod("DELETE", mcpIntegration);

    // CloudFront (single domain for OAuth + MCP)
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

    // CALLBACK_URL is set post-deploy by deploy.sh (avoids circular dependency with CloudFront)

    new events.Rule(this, "TokenRefreshRule", {
      schedule: events.Schedule.rate(cdk.Duration.hours(1)),
      targets: [new targets.LambdaFunction(oauthFn)],
    });

    new cdk.CfnOutput(this, "OAuthFunctionName", { value: oauthFn.functionName });
    new cdk.CfnOutput(this, "MiddlewareFunctionName", { value: middlewareFn.functionName });
    new cdk.CfnOutput(this, "OAuthEndpoint", { value: this.oauthEndpoint });
    new cdk.CfnOutput(this, "McpEndpoint", {
      value: `${this.oauthEndpoint}/mcp`,
      description: "MCP Streamable HTTP endpoint (same domain as OAuth)",
    });
    new cdk.CfnOutput(this, "OAuthClientId", {
      value: oauthClientId,
      description: "OAuth Client ID for Quick Desktop connector",
    });
    new cdk.CfnOutput(this, "FeishuRedirectUrl", {
      value: `${this.oauthEndpoint}/callback`,
      description: "Add this to Feishu app redirect URLs",
    });
  }
}
