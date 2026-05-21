import * as cdk from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import { Construct } from "constructs";

export class CognitoStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.userPool = new cognito.UserPool(this, "LarkMcpUserPool", {
      userPoolName: "lark-mcp-users",
      selfSignUpEnabled: false,
      signInAliases: { email: true },
      standardAttributes: {
        email: { required: true, mutable: false },
        fullname: { required: false, mutable: true },
      },
    });

    // Feilian SAML 2.0 Identity Provider
    // Metadata URL must be provided by the Feilian admin after configuration
    const felianMetadataUrl = this.node.tryGetContext("felianSamlMetadataUrl");

    if (felianMetadataUrl) {
      const samlProvider = new cognito.UserPoolIdentityProviderSaml(
        this,
        "FelianSaml",
        {
          userPool: this.userPool,
          name: "Feilian",
          metadata: cognito.UserPoolIdentityProviderSamlMetadata.url(
            felianMetadataUrl
          ),
          attributeMapping: {
            email:
              cognito.ProviderAttribute.other(
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
              ),
            fullname:
              cognito.ProviderAttribute.other(
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
              ),
          },
        }
      );

      this.userPool.registerIdentityProvider(samlProvider);
    }

    this.userPoolClient = this.userPool.addClient("LarkMcpClient", {
      userPoolClientName: "lark-mcp-agentcore",
      generateSecret: true,
      oAuth: {
        flows: { authorizationCodeGrant: true },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: ["https://localhost:3000/callback"],
      },
      supportedIdentityProviders: felianMetadataUrl
        ? [cognito.UserPoolClientIdentityProvider.custom("Feilian")]
        : [cognito.UserPoolClientIdentityProvider.COGNITO],
    });

    const domain = this.userPool.addDomain("LarkMcpDomain", {
      cognitoDomain: {
        domainPrefix: `lark-mcp-${cdk.Aws.ACCOUNT_ID}`,
      },
    });

    new cdk.CfnOutput(this, "UserPoolId", {
      value: this.userPool.userPoolId,
    });
    new cdk.CfnOutput(this, "UserPoolClientId", {
      value: this.userPoolClient.userPoolClientId,
    });
    new cdk.CfnOutput(this, "CognitoDomain", {
      value: domain.domainName,
    });
    new cdk.CfnOutput(this, "CognitoLoginUrl", {
      value: `https://lark-mcp-${cdk.Aws.ACCOUNT_ID}.auth.${cdk.Aws.REGION}.amazoncognito.com/login?client_id=${this.userPoolClient.userPoolClientId}&response_type=token&scope=openid+email+profile&redirect_uri=https://localhost:3000/callback`,
      description: "Cognito Hosted UI login URL for obtaining JWT",
    });
    new cdk.CfnOutput(this, "SamlSpMetadataUrl", {
      value: `https://cognito-idp.${cdk.Aws.REGION}.amazonaws.com/${this.userPool.userPoolId}/saml2/metadata`,
      description: "Download and upload to Feilian admin console as SP configuration",
    });
  }
}
