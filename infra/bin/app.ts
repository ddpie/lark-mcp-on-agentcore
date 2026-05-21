#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { OAuthStack } from "../lib/oauth-stack";
import { RuntimeStack } from "../lib/runtime-stack";

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION ?? "us-west-2",
};

const feishuAppId = app.node.tryGetContext("feishuAppId") || process.env.FEISHU_APP_ID || "";
const feishuAppSecret = app.node.tryGetContext("feishuAppSecret") || process.env.FEISHU_APP_SECRET || "";
const runtimeArn = app.node.tryGetContext("runtimeArn") || process.env.RUNTIME_ARN || "";
const customDomain = process.env.CUSTOM_DOMAIN || "";

if (!feishuAppId || !feishuAppSecret) {
  throw new Error(
    "Missing Feishu credentials. Provide via env (FEISHU_APP_ID + FEISHU_APP_SECRET) or -c flags."
  );
}

const oauth = new OAuthStack(app, "LarkMcpOAuth", {
  env,
  feishuAppId,
  feishuAppSecret,
  runtimeArn,
  customDomain,
});

const runtime = new RuntimeStack(app, "LarkMcpRuntime", {
  env,
  feishuAppId,
});
runtime.addDependency(oauth);
