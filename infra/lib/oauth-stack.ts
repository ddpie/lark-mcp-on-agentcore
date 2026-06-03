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
import * as snsSubscriptions from "aws-cdk-lib/aws-sns-subscriptions";
import { Construct } from "constructs";
import * as path from "path";
import * as fs from "fs";

export interface OAuthStackProps extends cdk.StackProps {
  runtimeArn?: string;
  customDomain?: string;
  webAclArn?: string;
  domainVerification?: string;
}

const LOG_RETENTION_MAP: Record<string, logs.RetentionDays> = {
  "30": logs.RetentionDays.ONE_MONTH,
  "90": logs.RetentionDays.THREE_MONTHS,
  "180": logs.RetentionDays.SIX_MONTHS,
  "365": logs.RetentionDays.ONE_YEAR,
};

// Default to a bounded retention so logs don't accumulate (and bill) forever
// when LOG_RETENTION_DAYS is unset. Operators can raise it via the env var.
const DEFAULT_LOG_RETENTION = logs.RetentionDays.THREE_MONTHS;

function createLogGroup(scope: Construct, id: string, fnName: string, retention?: logs.RetentionDays): logs.LogGroup {
  return new logs.LogGroup(scope, id, {
    logGroupName: `/aws/lambda/${fnName}`,
    retention: retention ?? DEFAULT_LOG_RETENTION,
    removalPolicy: cdk.RemovalPolicy.DESTROY,
  });
}

export class OAuthStack extends cdk.Stack {
  public readonly oauthEndpoint: string;
  public readonly secretPrefix: string;
  private readonly appSecretId: string;

  constructor(scope: Construct, id: string, props: OAuthStackProps) {
    super(scope, id, props);

    cdk.Tags.of(this).add("project", "lark-mcp-on-agentcore");

    const logRetentionEnv = process.env.LOG_RETENTION_DAYS ?? "";
    const logRetention = LOG_RETENTION_MAP[logRetentionEnv];

    const i18nPath = path.join(__dirname, "../../config/i18n.json");
    let i18n: Record<string, Record<string, Record<string, string>>>;
    try {
      i18n = JSON.parse(fs.readFileSync(i18nPath, "utf8"));
    } catch (e: any) {
      throw new Error(`Failed to load config/i18n.json: ${e.message}`, { cause: e });
    }
    const lang = process.env.LARK_LANG || "zh";
    const dt = i18n.dashboard[lang] || i18n.dashboard.en;
    const an = i18n.alarmNames?.[lang] || i18n.alarmNames?.en || {};

    const thresholdsPath = path.join(__dirname, "../../config/alarm-thresholds.json");
    const localOverridesPath = path.join(__dirname, "../../.local/alarm-thresholds.json");
    interface AlarmThreshold { threshold: number; period: number; evaluationPeriods: number }
    let thresholds: Record<string, AlarmThreshold>;
    try {
      thresholds = JSON.parse(fs.readFileSync(thresholdsPath, "utf8"));
    } catch (e: any) {
      throw new Error(`Failed to load config/alarm-thresholds.json: ${e.message}`, { cause: e });
    }
    if (fs.existsSync(localOverridesPath)) {
      const overrides: Record<string, number> = JSON.parse(fs.readFileSync(localOverridesPath, "utf8"));
      for (const [key, val] of Object.entries(overrides)) {
        if (thresholds[key]) thresholds[key].threshold = val;
      }
    }
    const th = (key: string) => thresholds[key] || { threshold: 5, period: 300, evaluationPeriods: 2 };

    this.secretPrefix = "lark-mcp-on-agentcore/users";
    this.appSecretId = "lark-mcp-on-agentcore/feishu-app";
    const stateSecretParam = "/lark-mcp-on-agentcore/state-secret";

    // Import the secret by name — deploy.sh creates/updates it outside CDK
    // so that `cdk deploy` never overwrites the real credentials with placeholders.
    const appSecret = secretsmanager.Secret.fromSecretNameV2(
      this, "FeishuAppSecret", this.appSecretId
    );

    const oauthClientId = "lark-mcp-on-agentcore";

    const oauthFnName = `${this.stackName}-oauth`;
    const oauthLogGroup = createLogGroup(this, "OAuthLogGroup", oauthFnName, logRetention);
    const oauthFn = new nodejs.NodejsFunction(this, "OAuthFunction", {
      functionName: oauthFnName,
      runtime: lambda.Runtime.NODEJS_20_X,
      entry: path.join(__dirname, "../../lambda/token-refresh-shim/index.ts"),
      projectRoot: path.join(__dirname, "../.."),
      depsLockFilePath: path.join(__dirname, "../package-lock.json"),
      handler: "handler",
      timeout: cdk.Duration.seconds(120),
      memorySize: 256,
      // Cap concurrency so a traffic spike (or a WAF bypass) can't scale this
      // function to the whole account quota and starve other Lambdas / run up
      // cost. Override via OAUTH_RESERVED_CONCURRENCY.
      reservedConcurrentExecutions: parseInt(process.env.OAUTH_RESERVED_CONCURRENCY || "20", 10),
      logGroup: oauthLogGroup,
      environment: {
        CALLBACK_URL: "SET_AFTER_DEPLOY",
        SECRET_PREFIX: this.secretPrefix,
        APP_SECRET_ID: this.appSecretId,
        STATE_SECRET_PARAM: stateSecretParam,
        OAUTH_CLIENT_ID: oauthClientId,
        OAUTH_CLIENT_SECRET: "SET_AFTER_DEPLOY",
        ALLOWED_DOMAINS: props.customDomain || "",
        DOMAIN_VERIFICATION: props.domainVerification || "",
      },
      // @aws-sdk/lib-dynamodb is not in the Node.js 20 runtime; bundle it.
      bundling: { externalModules: ["@aws-sdk/client-*"], minify: true, target: "node20" },
    });

    appSecret.grantRead(oauthFn);
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["ssm:GetParameter"],
      resources: [`arn:aws:ssm:${this.region}:${this.account}:parameter${stateSecretParam}`],
    }));
    // Per-user token secrets only. Scoped to .../users/* — NOT the whole project
    // prefix — so a compromised OAuth Lambda cannot overwrite the feishu-app
    // master credential (read of which is granted separately via grantRead above).
    oauthFn.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:CreateSecret",
        // Cleanup of revoked users (Feishu code 20016) during the refresh cycle.
        "secretsmanager:DeleteSecret",
        // Restore a secret in its 7-day recovery window when the user re-authorizes
        // before scheduled deletion completes (storeToken's pending-deletion path).
        "secretsmanager:RestoreSecret",
        // Required when CreateSecret is called with embedded Tags. Without this,
        // strict orgs with explicit Deny on TagResource block first-time
        // authorization for new users.
        "secretsmanager:TagResource",
      ],
      resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:${this.secretPrefix}/*`],
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

    // OpenID → stable userId mapping (migrated from Secrets Manager to DDB for cost)
    const openidTable = new dynamodb.Table(this, "OpenIdMap", {
      tableName: "lark-mcp-on-agentcore-openid-map",
      partitionKey: { name: "openId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    openidTable.grantReadWriteData(oauthFn);
    oauthFn.addEnvironment("OPENID_TABLE", openidTable.tableName);

    // Middleware Lambda (MCP proxy: token verify → SM → AgentCore)
    const middlewareFnName = `${this.stackName}-middleware`;
    const middlewareLogGroup = createLogGroup(this, "MiddlewareLogGroup", middlewareFnName, logRetention);
    const middlewareFn = new nodejs.NodejsFunction(this, "MiddlewareFunction", {
      functionName: middlewareFnName,
      runtime: lambda.Runtime.NODEJS_20_X,
      entry: path.join(__dirname, "../../lambda/mcp-middleware/index.ts"),
      projectRoot: path.join(__dirname, "../.."),
      depsLockFilePath: path.join(__dirname, "../package-lock.json"),
      handler: "handler",
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      // Hot path — cap concurrency to bound the DoS/cost blast radius (sized to
      // the AgentCore Runtime's capacity). Override via MIDDLEWARE_RESERVED_CONCURRENCY.
      reservedConcurrentExecutions: parseInt(process.env.MIDDLEWARE_RESERVED_CONCURRENCY || "50", 10),
      logGroup: middlewareLogGroup,
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

    // Single API Gateway: all routes (OAuth + MCP). Stage-level throttling is a
    // region-independent request-rate cap that applies even when the optional
    // CloudFront WAF is skipped (SKIP_WAF) or bypassed by hitting execute-api
    // directly — without it the OAuth/MCP endpoints would have no rate control.
    const api = new apigateway.RestApi(this, "OAuthApi", {
      restApiName: "lark-mcp-on-agentcore-oauth",
      deployOptions: {
        throttlingRateLimit: parseInt(process.env.APIGW_RATE_LIMIT || "50", 10),
        throttlingBurstLimit: parseInt(process.env.APIGW_BURST_LIMIT || "100", 10),
      },
    });
    const oauthIntegration = new apigateway.LambdaIntegration(oauthFn);
    const mcpIntegration = new apigateway.LambdaIntegration(middlewareFn);

    api.root.addResource("authorize").addMethod("GET", oauthIntegration);
    api.root.addResource("callback").addMethod("GET", oauthIntegration);
    api.root.addResource("token").addMethod("POST", oauthIntegration);
    const wellKnown = api.root.addResource(".well-known");
    wellKnown.addResource("oauth-authorization-server").addMethod("GET", oauthIntegration);
    // AWS Security Agent domain-ownership verification (HTTP route method).
    // Inert unless DOMAIN_VERIFICATION is set on the OAuth Lambda (deploy.sh).
    wellKnown
      .addResource("aws")
      .addResource("securityagent-domain-verification.json")
      .addMethod("GET", oauthIntegration);

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
      schedule: events.Schedule.rate(cdk.Duration.minutes(30)),
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
      alarmName: an.token_lost,
      metric: tokenLossFilter.metric({ statistic: "Sum", period: cdk.Duration.seconds(th("token_lost").period) }),
      threshold: th("token_lost").threshold,
      evaluationPeriods: th("token_lost").evaluationPeriods,
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
      alarmName: an.refresh_failed,
      metric: refreshFailedFilter.metric({ statistic: "Sum", period: cdk.Duration.seconds(th("refresh_failed").period) }),
      threshold: th("refresh_failed").threshold,
      evaluationPeriods: th("refresh_failed").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    }).addAlarmAction(alarmAction);

    // Lambda errors (any uncaught throw / runtime error).
    new cloudwatch.Alarm(this, "OAuthErrorAlarm", {
      alarmName: an.oauth_errors,
      metric: oauthFn.metricErrors({ period: cdk.Duration.seconds(th("oauth_errors").period) }),
      threshold: th("oauth_errors").threshold,
      evaluationPeriods: th("oauth_errors").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);
    new cloudwatch.Alarm(this, "MiddlewareErrorAlarm", {
      alarmName: an.middleware_errors,
      metric: middlewareFn.metricErrors({ period: cdk.Duration.seconds(th("middleware_errors").period) }),
      threshold: th("middleware_errors").threshold,
      evaluationPeriods: th("middleware_errors").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    // MCP latency P95 alarm — user experience degradation
    new cloudwatch.Alarm(this, "McpLatencyAlarm", {
      alarmName: an.mcp_latency,
      metric: new cloudwatch.Metric({
        namespace: "LarkMcpOnAgentCore", metricName: "McpLatencyMs",
        statistic: "p95", period: cdk.Duration.seconds(th("mcp_latency").period),
      }),
      threshold: th("mcp_latency").threshold,
      evaluationPeriods: th("mcp_latency").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    }).addAlarmAction(alarmAction);

    // Feishu not-authorized spike — possible mass token revocation
    new cloudwatch.Alarm(this, "FeishuNotAuthAlarm", {
      alarmName: an.feishu_not_auth,
      metric: new cloudwatch.Metric({
        namespace: "LarkMcpOnAgentCore", metricName: "FeishuNotAuthorized",
        statistic: "Sum", period: cdk.Duration.seconds(th("feishu_not_auth").period),
      }),
      threshold: th("feishu_not_auth").threshold,
      evaluationPeriods: th("feishu_not_auth").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    // Lambda concurrent executions — concurrency_pct.threshold is percentage of account quota
    const concurrencyQuota = parseInt(process.env.LAMBDA_CONCURRENCY_QUOTA || "1000", 10);
    new cloudwatch.Alarm(this, "MiddlewareConcurrencyAlarm", {
      alarmName: an.concurrency,
      metric: middlewareFn.metric("ConcurrentExecutions", { statistic: "Maximum", period: cdk.Duration.seconds(th("concurrency_pct").period) }),
      threshold: Math.floor(concurrencyQuota * th("concurrency_pct").threshold / 100),
      evaluationPeriods: th("concurrency_pct").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    // Lambda throttles — capacity issue
    new cloudwatch.Alarm(this, "ThrottleAlarm", {
      alarmName: an.throttles,
      metric: middlewareFn.metricThrottles({ period: cdk.Duration.seconds(th("throttles").period) }),
      threshold: th("throttles").threshold,
      evaluationPeriods: th("throttles").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    // API Gateway 5xx (server-side errors at the gateway level)
    new cloudwatch.Alarm(this, "ApiGateway5xxAlarm", {
      alarmName: an.apigw_5xx,
      metric: new cloudwatch.Metric({
        namespace: "AWS/ApiGateway", metricName: "5XXError",
        dimensionsMap: { ApiName: "lark-mcp-on-agentcore-oauth" },
        statistic: "Sum", period: cdk.Duration.seconds(th("apigw_5xx").period),
      }),
      threshold: th("apigw_5xx").threshold,
      evaluationPeriods: th("apigw_5xx").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    // --- Observability: daily operation metrics ---

    // AgentCore upstream 5xx
    const agentCore5xxFilter = new logs.MetricFilter(this, "AgentCore5xxFilter", {
      logGroup: middlewareFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "agentcore_5xx"),
      metricName: "AgentCore5xx",
      metricNamespace: "LarkMcpOnAgentCore",
    });
    new cloudwatch.Alarm(this, "AgentCore5xxAlarm", {
      alarmName: an.upstream_5xx,
      metric: agentCore5xxFilter.metric({ statistic: "Sum", period: cdk.Duration.seconds(th("upstream_5xx").period) }),
      threshold: th("upstream_5xx").threshold,
      evaluationPeriods: th("upstream_5xx").evaluationPeriods,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(alarmAction);

    // Feishu API slow calls (>3s)
    new logs.MetricFilter(this, "FeishuSlowFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "feishu_slow"),
      metricName: "FeishuSlow",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // AgentCore slow calls (>5s)
    new logs.MetricFilter(this, "AgentCoreSlowFilter", {
      logGroup: middlewareFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "agentcore_slow"),
      metricName: "AgentCoreSlow",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // MCP proxy request success (for traffic volume + latency dashboarding)
    new logs.MetricFilter(this, "McpRequestOkFilter", {
      logGroup: middlewareFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "mcp_request_ok"),
      metricName: "McpRequestOk",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // MCP proxy latency (extract durationMs from successful requests)
    new logs.MetricFilter(this, "McpLatencyFilter", {
      logGroup: middlewareFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "mcp_request_ok"),
      metricName: "McpLatencyMs",
      metricNamespace: "LarkMcpOnAgentCore",
      metricValue: "$.durationMs",
    });

    // Auth failure count (token_verify_failed + auth_missing_or_invalid)
    new logs.MetricFilter(this, "AuthFailFilter", {
      logGroup: middlewareFn.logGroup,
      filterPattern: logs.FilterPattern.anyTerm("token_verify_failed", "auth_missing_or_invalid"),
      metricName: "AuthFail",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // OAuth authorize started (funnel top)
    new logs.MetricFilter(this, "OAuthStartFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "oauth_authorize_start"),
      metricName: "OAuthAuthorizeStart",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // OAuth callback success (funnel bottom)
    new logs.MetricFilter(this, "OAuthCallbackOkFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "oauth_callback_success"),
      metricName: "OAuthCallbackSuccess",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // New user authorized
    new logs.MetricFilter(this, "NewUserFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "new_user_authorized"),
      metricName: "NewUserAuthorized",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // Active users (from refresh cycle)
    new logs.MetricFilter(this, "ActiveUsersFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "refresh_cycle"),
      metricName: "ActiveUsers",
      metricNamespace: "LarkMcpOnAgentCore",
      metricValue: "$.total",
    });

    // Feishu token not authorized (user needs re-auth or first-time auth)
    new logs.MetricFilter(this, "FeishuNotAuthorizedFilter", {
      logGroup: middlewareFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "feishu_not_authorized"),
      metricName: "FeishuNotAuthorized",
      metricNamespace: "LarkMcpOnAgentCore",
    });

    // Feishu API slow call latency (extract durationMs for percentile tracking)
    new logs.MetricFilter(this, "FeishuSlowLatencyFilter", {
      logGroup: oauthFn.logGroup,
      filterPattern: logs.FilterPattern.stringValue("$.event", "=", "feishu_slow"),
      metricName: "FeishuSlowLatencyMs",
      metricNamespace: "LarkMcpOnAgentCore",
      metricValue: "$.durationMs",
    });

    // Feishu webhook relay: SNS → Lambda (format to card) → Feishu bot webhook
    const alarmWebhook = process.env.ALARM_WEBHOOK_URL || "";
    if (alarmWebhook) {
      const webhookFnName = `${this.stackName}-alarm-webhook`;
      const webhookLogGroup = createLogGroup(this, "WebhookLogGroup", webhookFnName, logRetention);
      const webhookFn = new nodejs.NodejsFunction(this, "AlarmWebhookFunction", {
        functionName: webhookFnName,
        runtime: lambda.Runtime.NODEJS_20_X,
        entry: path.join(__dirname, "../../lambda/alarm-webhook/index.ts"),
        projectRoot: path.join(__dirname, "../.."),
        depsLockFilePath: path.join(__dirname, "../package-lock.json"),
        handler: "handler",
        timeout: cdk.Duration.seconds(10),
        memorySize: 128,
        logGroup: webhookLogGroup,
        environment: {
          FEISHU_WEBHOOK_URL: alarmWebhook,
          FEISHU_WEBHOOK_SECRET: process.env.ALARM_WEBHOOK_SECRET || "",
          FEISHU_WEBHOOK_KEYWORD: process.env.ALARM_WEBHOOK_KEYWORD || "",
          DEPLOY_LANG: lang,
        },
        bundling: { externalModules: [], minify: true, target: "node20" },
      });
      alarmTopic.addSubscription(new snsSubscriptions.LambdaSubscription(webhookFn));
    }

    // --- CloudWatch Dashboard ---
    const ns = "LarkMcpOnAgentCore";
    const m = (metricName: string, opts: Partial<cloudwatch.MetricProps> = {}) =>
      new cloudwatch.Metric({ namespace: ns, metricName, statistic: "Sum", period: cdk.Duration.minutes(5), label: opts.label || `${metricName}${opts.statistic && opts.statistic !== "Sum" ? ` (${opts.statistic})` : ""}`, ...opts });
    const dashboard = new cloudwatch.Dashboard(this, "ObservabilityDashboard", {
      dashboardName: "lark-mcp-on-agentcore",
    });

    // Section: Alarm Overview (top of dashboard for at-a-glance status)
    dashboard.addWidgets(new cloudwatch.TextWidget({ markdown: `## ${dt.alarms}`, width: 24, height: 1 }));
    dashboard.addWidgets(
      new cloudwatch.AlarmStatusWidget({
        title: dt.alarms,
        alarms: [
          cloudwatch.Alarm.fromAlarmArn(this, "RefTokenLost", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.token_lost}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefRefreshFailed", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.refresh_failed}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefUpstream5xx", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.upstream_5xx}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefLatency", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.mcp_latency}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefNotAuth", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.feishu_not_auth}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefConcurrency", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.concurrency}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefThrottle", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.throttles}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefApiGw5xx", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.apigw_5xx}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefOAuthErr", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.oauth_errors}`),
          cloudwatch.Alarm.fromAlarmArn(this, "RefMwErr", `arn:aws:cloudwatch:${this.region}:${this.account}:alarm:${an.middleware_errors}`),
        ],
        width: 24,
      }),
    );

    // Section: MCP Traffic
    dashboard.addWidgets(new cloudwatch.TextWidget({ markdown: `## ${dt.requests}`, width: 24, height: 1 }));
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: dt.requests,
        left: [m("McpRequestOk")],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.latency,
        left: [
          m("McpLatencyMs", { statistic: "Average" }),
          m("McpLatencyMs", { statistic: "p95" }),
          m("McpLatencyMs", { statistic: "p99" }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.errors,
        left: [m("AgentCore5xx"), m("AgentCoreSlow"), m("FeishuSlow")],
        width: 8,
      }),
    );

    // Section: Lambda
    dashboard.addWidgets(new cloudwatch.TextWidget({ markdown: `## ${dt.lambda_invocations}`, width: 24, height: 1 }));
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: dt.lambda_invocations,
        left: [
          oauthFn.metricInvocations({ label: "OAuth", period: cdk.Duration.minutes(5) }),
          middlewareFn.metricInvocations({ label: "Middleware", period: cdk.Duration.minutes(5) }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.lambda_duration,
        left: [
          oauthFn.metricDuration({ label: "OAuth (avg)", statistic: "Average", period: cdk.Duration.minutes(5) }),
          oauthFn.metricDuration({ label: "OAuth (p95)", statistic: "p95", period: cdk.Duration.minutes(5) }),
          middlewareFn.metricDuration({ label: "Middleware (avg)", statistic: "Average", period: cdk.Duration.minutes(5) }),
          middlewareFn.metricDuration({ label: "Middleware (p95)", statistic: "p95", period: cdk.Duration.minutes(5) }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.lambda_errors,
        left: [
          oauthFn.metricErrors({ label: "OAuth Errors", period: cdk.Duration.minutes(5) }),
          middlewareFn.metricErrors({ label: "Middleware Errors", period: cdk.Duration.minutes(5) }),
        ],
        right: [
          oauthFn.metricThrottles({ label: "OAuth Throttles", period: cdk.Duration.minutes(5) }),
          middlewareFn.metricThrottles({ label: "Middleware Throttles", period: cdk.Duration.minutes(5) }),
        ],
        rightYAxis: { label: dt.lambda_throttles },
        width: 8,
      }),
    );

    // Section: OAuth & Token
    dashboard.addWidgets(new cloudwatch.TextWidget({ markdown: `## ${dt.funnel}`, width: 24, height: 1 }));
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: dt.funnel,
        left: [
          m("OAuthAuthorizeStart", { period: cdk.Duration.hours(1) }),
          m("OAuthCallbackSuccess", { period: cdk.Duration.hours(1) }),
          m("NewUserAuthorized", { period: cdk.Duration.hours(1) }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.refresh,
        left: [
          m("RefreshFailed", { period: cdk.Duration.hours(1) }),
          m("TokenLost", { period: cdk.Duration.hours(1) }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.users,
        left: [m("ActiveUsers", { statistic: "Maximum", period: cdk.Duration.hours(1) })],
        right: [m("AuthFail")],
        width: 8,
      }),
    );

    // Section: Infrastructure
    dashboard.addWidgets(new cloudwatch.TextWidget({ markdown: `## ${dt.api_4xx_5xx}`, width: 24, height: 1 }));
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: dt.api_4xx_5xx,
        left: [
          new cloudwatch.Metric({ namespace: "AWS/ApiGateway", metricName: "4XXError", dimensionsMap: { ApiName: "lark-mcp-on-agentcore-oauth" }, statistic: "Sum", period: cdk.Duration.minutes(5), label: "4xx" }),
          new cloudwatch.Metric({ namespace: "AWS/ApiGateway", metricName: "5XXError", dimensionsMap: { ApiName: "lark-mcp-on-agentcore-oauth" }, statistic: "Sum", period: cdk.Duration.minutes(5), label: "5xx" }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.lambda_concurrent,
        left: [
          oauthFn.metric("ConcurrentExecutions", { label: "OAuth", statistic: "Maximum", period: cdk.Duration.minutes(5) }),
          middlewareFn.metric("ConcurrentExecutions", { label: "Middleware", statistic: "Maximum", period: cdk.Duration.minutes(5) }),
        ],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: dt.not_authorized,
        left: [m("FeishuNotAuthorized")],
        right: [m("FeishuSlowLatencyMs", { statistic: "Average" }), m("FeishuSlowLatencyMs", { statistic: "p95" })],
        rightYAxis: { label: dt.feishu_latency },
        width: 8,
      }),
    );


    const dashboardUrl = `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards/dashboard/lark-mcp-on-agentcore`;
    new cdk.CfnOutput(this, "DashboardUrl", { value: dashboardUrl, description: "CloudWatch observability dashboard" });
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
