import * as cdk from "aws-cdk-lib";
import * as ecr_assets from "aws-cdk-lib/aws-ecr-assets";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";
import * as path from "path";

export interface RuntimeStackProps extends cdk.StackProps {}

export class RuntimeStack extends cdk.Stack {
  public readonly runtimeRole: iam.Role;
  public readonly imageUri: string;

  constructor(scope: Construct, id: string, props: RuntimeStackProps) {
    super(scope, id, props);

    cdk.Tags.of(this).add("project", "lark-mcp-on-agentcore");

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
    // Container fetches APP_SECRET from Secrets Manager at startup.
    this.runtimeRole.addToPolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:GetSecretValue"],
      resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:lark-mcp-on-agentcore/feishu-app-*`],
    }));

    // Outputs consumed by deploy.sh to wire AgentCore Runtime + Lambda env.
    new cdk.CfnOutput(this, "ImageUri", { value: image.imageUri });
    new cdk.CfnOutput(this, "RuntimeRoleArn", { value: this.runtimeRole.roleArn });
  }
}
