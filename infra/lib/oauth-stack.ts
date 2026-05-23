import * as cdk from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as nodejs from "aws-cdk-lib/aws-lambda-nodejs";
import * as apigateway from "aws-cdk-lib/aws-apigateway";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as events from "aws-cdk-lib/aws-events";
import * as targets from "aws-cdk-lib/aws-events-targets";
import * as iam from "aws-cdk-lib/aws-iam";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as cwActions from "aws-cdk-lib/aws-cloudwatch-actions";
import * as logs from "aws-cdk-lib/aws-logs";
import * as sns from "aws-cdk-lib/aws-sns";
import { Construct } from "constructs";
import * as path from "path";

export interface OAuthStackProps extends cdk.StackProps {
  runtimeArn?: string;
  customDomain?: string;
  webAclArn?: string;
}

export class OAuthStack extends cdk.Stack {
  public readonly oauthEndpoint: string;
  public readonly secretPrefix: string;
  private readonly appSecretId: string;

  constructor(scope: Construct, id: string, props: OAuthStackProps) {
    super(scope, id, props);

    cdk.Tags.of(this).add("project", "lark-mcp-on-agentcore");

    this.secretPrefix = "lark-mcp-on-agentcore/users";
    this.appSecretId = "lark-mcp-on-agentcore/feishu-app";
    const stateSecretParam = "/lark-mcp-on-agentcore/state-secret";

    // Import the secret by name — deploy.sh creates/updates it outside CDK
    // so that `cdk deploy` never overwrites the real credentials with placeholders.
    const appSecret = secretsmanager.Secret.fromSecretNameV2(
      this, "FeishuAppSecret", this.appSecretId
    );

    const oauthClientId = "lark-mcp-on-agentcore";

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
        OPENID_PREFIX: "lark-mcp-on-agentcore/openid-map",
        APP_SECRET_ID: this.appSecretId,
        STATE_SECRET: "SET_AFTER_DEPLOY",
        OAUTH_CLIENT_ID: oauthClientId,
        OAUTH_CLIENT_SECRET: "SET_AFTER_DEPLOY",
        ALLOWED_DOMAINS: props.customDomain || "",
      },
      // @aws-sdk/lib-dynamodb is not in the Node.js 20 runtime; bundle it.
      bundling: { externalModules: ["@aws-sdk/client-*"], minify: true, target: "node20" },
    });

    appSecret.grantRead(oauthFn);
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        // Required when CreateSecret is called with embedded Tags. Without this,
        // strict orgs with explicit Deny on TagResource block first-time
        // authorization for new users.
        "secretsmanager:TagResource",
      ],
      resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:lark-mcp-on-agentcore/*`],
    }));
    // ListSecrets is an account-level action and does not honor resource-scoping
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:ListSecrets"],
      resources: ["*"],
    }));

    // OAuth authorization codes
    const codeTable = new dynamodb.Table(this, "OAuthCodes", {
      tableName: "lark-mcp-on-agentcore-oauth-codes",
      partitionKey: { name: "code", type: dynamodb.AttributeType.STRING },
      timeToLiveAttribute: "ttl",
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    codeTable.grantReadWriteData(oauthFn);
    oauthFn.addEnvironment("CODE_TABLE", codeTable.tableName);

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
        STATE_SECRET_PARAM: stateSecretParam,
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
      resources: [`arn:aws:ssm:${this.region}:${this.account}:parameter${stateSecretParam}`],
    }));
    middlewareFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["bedrock-agentcore:InvokeAgentRuntime"],
      resources: [`arn:aws:bedrock-agentcore:${this.region}:${this.account}:runtime/*`],
    }));

    // Single API Gateway: all routes (OAuth + MCP)
    const api = new apigateway.RestApi(this, "OAuthApi", { restApiName: "lark-mcp-on-agentcore-oauth" });
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
      webAclId: props.webAclArn,
    });

    this.oauthEndpoint = `https://${distribution.distributionDomainName}`;

    // CALLBACK_URL is set post-deploy by deploy.sh (avoids circular dependency with CloudFront)

    new events.Rule(this, "TokenRefreshRule", {
      schedule: events.Schedule.rate(cdk.Duration.hours(1)),
      targets: [new targets.LambdaFunction(oauthFn)],
    });

    // SNS topic + CloudWatch alarms.
    // Subscribe an email/Slack/Lark webhook after deploy:
    //   aws sns subscribe --topic-arn <AlarmTopicArn> --protocol email --notification-endpoint you@example.com
    const alarmTopic = new sns.Topic(this, "AlarmTopic", {
      topicName: "lark-mcp-on-agentcore-alarms",
      displayName: "Lark MCP on AgentCore alarms",
    });
    const alarmAction = new cwActions.SnsAction(alarmTopic);

    // Token loss — most severe: refresh_token consumed but new tokens not stored.
    const tokenLossFilter = new logs.MetricFilter(this, "TokenLossFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "store_token_lost"),
      metricName: "TokenLost",
      metricNamespace: "LarkMcpOnAgentCore",
    });
    new cloudwatch.Alarm(this, "TokenLossAlarm", {
      alarmName: "lark-mcp-on-agentcore-token-lost",
      metric: tokenLossFilter.metric({ statistic: "Sum", period: cdk.Duration.minutes(1) }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    }).addAlarmAction(alarmAction);

    // Per-cycle refresh failure count. Matches the structured log emitted
    // at the end of each EventBridge cron invocation in token-refresh-shim.
    const refreshFailedFilter = new logs.MetricFilter(this, "RefreshFailedFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.all(
        logs.FilterPattern.stringValue("$.event", "=", "refresh_cycle"),
        logs.FilterPattern.exists("$.failed"),
      ),
      metricName: "RefreshFailed",
      metricNamespace: "LarkMcpOnAgentCore",
      metricValue: "$.failed",
    });
    new cloudwatch.Alarm(this, "RefreshFailedAlarm", {
      alarmName: "lark-mcp-on-agentcore-refresh-failed",
      metric: refreshFailedFilter.metric({ statistic: "Sum", period: cdk.Duration.minutes(5) }),
      threshold: 3,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    }).addAlarmAction(alarmAction);

    // Lambda errors (any uncaught throw / runtime error).
    new cloudwatch.Alarm(this, "OAuthErrorAlarm", {
      alarmName: "lark-mcp-on-agentcore-oauth-errors",
      metric: oauthFn.metricErrors({ period: cdk.Duration.minutes(5) }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);
    new cloudwatch.Alarm(this, "MiddlewareErrorAlarm", {
      alarmName: "lark-mcp-on-agentcore-middleware-errors",
      metric: middlewareFn.metricErrors({ period: cdk.Duration.minutes(5) }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    new cdk.CfnOutput(this, "AlarmTopicArn", { value: alarmTopic.topicArn });
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
