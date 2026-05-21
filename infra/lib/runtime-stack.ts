import * as cdk from "aws-cdk-lib";
import * as ecr_assets from "aws-cdk-lib/aws-ecr-assets";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";
import * as path from "path";

export interface RuntimeStackProps extends cdk.StackProps {
  feishuAppId: string;
}

export class RuntimeStack extends cdk.Stack {
  public readonly runtimeRole: iam.Role;
  public readonly imageUri: string;

  constructor(scope: Construct, id: string, props: RuntimeStackProps) {
    super(scope, id, props);

    // Docker image (auto build + push)
    const image = new ecr_assets.DockerImageAsset(this, "LarkMcpImage", {
      directory: path.join(__dirname, "../../docker"),
      platform: ecr_assets.Platform.LINUX_ARM64,
    });
    this.imageUri = image.imageUri;

    // IAM role for AgentCore Runtime
    this.runtimeRole = new iam.Role(this, "RuntimeRole", {
      assumedBy: new iam.ServicePrincipal("bedrock-agentcore.amazonaws.com"),
    });
    this.runtimeRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonEC2ContainerRegistryReadOnly")
    );

    // Outputs + manual steps
    new cdk.CfnOutput(this, "ImageUri", { value: image.imageUri });
    new cdk.CfnOutput(this, "RuntimeRoleArn", { value: this.runtimeRole.roleArn });
    new cdk.CfnOutput(this, "DeployCommand", {
      value: [
        "Create AgentCore Runtime manually (no CDK L2 construct yet):",
        `  agentcore create --name larkmcp --build Container --protocol MCP --skip-git`,
        `  # Configure: image=${image.imageUri}, role=${this.runtimeRole.roleArn}`,
        `  # Env: APP_ID=${props.feishuAppId}, APP_SECRET=<from-SM>, LARKSUITE_CLI_BRAND=feishu`,
        `  # requestHeaderAllowlist: [X-User-Access-Token, X-Runtime-User-Id]`,
        `  agentcore deploy`,
      ].join("\n"),
    });
  }
}
