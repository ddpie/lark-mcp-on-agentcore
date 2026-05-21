#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { CognitoStack } from "../lib/cognito-stack";
import { OAuthStack } from "../lib/oauth-stack";
import { RuntimeStack } from "../lib/runtime-stack";
import { MiddlewareStack } from "../lib/middleware-stack";

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION ?? "us-west-2",
};

const feishuAppId = app.node.tryGetContext("feishuAppId");
const feishuAppSecret = app.node.tryGetContext("feishuAppSecret");
const runtimeArn = app.node.tryGetContext("runtimeArn") || "";

if (!feishuAppId || !feishuAppSecret) {
  throw new Error(
    "Missing required context. Usage:\n" +
    "  cdk deploy --all -c feishuAppId=cli_xxx -c feishuAppSecret=xxx\n" +
    "After AgentCore deploy, redeploy middleware with:\n" +
    "  cdk deploy LarkMcpMiddleware -c runtimeArn=arn:aws:bedrock-agentcore:..."
  );
}

const cognito = new CognitoStack(app, "LarkMcpCognito", { env });

const oauth = new OAuthStack(app, "LarkMcpOAuth", { env, feishuAppId, feishuAppSecret });

const runtime = new RuntimeStack(app, "LarkMcpRuntime", {
  env,
  feishuAppId,
  feishuAppSecret,
  secretPrefix: oauth.secretPrefix,
  oauthEndpoint: oauth.oauthEndpoint,
});
runtime.addDependency(oauth);

const middleware = new MiddlewareStack(app, "LarkMcpMiddleware", {
  env,
  runtimeArn,
  secretPrefix: oauth.secretPrefix,
  oauthEndpoint: oauth.oauthEndpoint,
  userPool: cognito.userPool,
  userPoolClient: cognito.userPoolClient,
});
middleware.addDependency(oauth);
middleware.addDependency(cognito);
