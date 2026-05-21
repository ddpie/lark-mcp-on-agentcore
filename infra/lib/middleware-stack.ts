import * as cdk from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as nodejs from "aws-cdk-lib/aws-lambda-nodejs";
import * as iam from "aws-cdk-lib/aws-iam";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as apigateway from "aws-cdk-lib/aws-apigateway";
import { Construct } from "constructs";
import * as path from "path";

export interface MiddlewareStackProps extends cdk.StackProps {
  runtimeArn: string;
  secretPrefix: string;
  oauthEndpoint: string;
  userPool: cognito.IUserPool;
  userPoolClient: cognito.IUserPoolClient;
}

export class MiddlewareStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: MiddlewareStackProps) {
    super(scope, id, props);

    // Lambda: MCP middleware (JWT → SM → AgentCore)
    const middlewareFn = new nodejs.NodejsFunction(this, "MiddlewareFunction", {
      runtime: lambda.Runtime.NODEJS_20_X,
      entry: path.join(__dirname, "../../lambda/mcp-middleware/index.ts"),
      handler: "handler",
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      environment: {
        RUNTIME_ARN: props.runtimeArn,
        SECRET_PREFIX: props.secretPrefix,
        AUTHORIZE_BASE: props.oauthEndpoint,
        AWS_REGION: this.region,
      },
      bundling: {
        externalModules: ["@aws-sdk/*", "@smithy/*", "@aws-crypto/*"],
        minify: true,
        target: "node20",
      },
    });

    // Grant: read user tokens from SM
    middlewareFn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["secretsmanager:GetSecretValue"],
        resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:${props.secretPrefix}/*`],
      })
    );

    // Grant: invoke AgentCore Runtime (use wildcard if ARN not yet known)
    middlewareFn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["bedrock-agentcore:InvokeAgentRuntime"],
        resources: [props.runtimeArn || `arn:aws:bedrock-agentcore:${this.region}:${this.account}:runtime/*`],
      })
    );

    // API Gateway: MCP endpoint with Cognito authorizer
    const api = new apigateway.RestApi(this, "McpApi", {
      restApiName: "lark-mcp",
      description: "Lark MCP endpoint (Cognito auth → AgentCore)",
    });

    const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, "CognitoAuth", {
      cognitoUserPools: [props.userPool],
    });

    api.root.addResource("mcp").addMethod("POST",
      new apigateway.LambdaIntegration(middlewareFn),
      {
        authorizer,
        authorizationType: apigateway.AuthorizationType.COGNITO,
      }
    );

    // Outputs
    new cdk.CfnOutput(this, "McpEndpoint", {
      value: `${api.url}mcp`,
      description: "MCP Streamable HTTP endpoint (requires Cognito JWT)",
    });
  }
}
