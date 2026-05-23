#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { OAuthStack } from "../lib/oauth-stack";
import { RuntimeStack } from "../lib/runtime-stack";
import { WafStack } from "../lib/waf-stack";

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION ?? "us-west-2";
const env = { account, region };

const runtimeArn = app.node.tryGetContext("runtimeArn") || process.env.RUNTIME_ARN || "";
const customDomain = process.env.CUSTOM_DOMAIN || "";

// CloudFront-scope WAF must live in us-east-1 regardless of deploy region.
// Set SKIP_WAF=1 to omit the WAF stack (e.g., for region-locked tenants).
const skipWaf = process.env.SKIP_WAF === "1";
const waf = skipWaf ? undefined : new WafStack(app, "LarkMcpOnAgentCoreWaf", {
  env: { account, region: "us-east-1" },
  crossRegionReferences: true,
});

const oauth = new OAuthStack(app, "LarkMcpOnAgentCoreOAuth", {
  env,
  runtimeArn,
  customDomain,
  webAclArn: waf?.webAclArn,
  crossRegionReferences: !skipWaf,
});
if (waf) oauth.addDependency(waf);

const runtime = new RuntimeStack(app, "LarkMcpOnAgentCoreRuntime", { env });
runtime.addDependency(oauth);
