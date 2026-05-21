import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { SignatureV4 } from '@smithy/signature-v4';
import { Sha256 } from '@aws-crypto/sha256-js';
import { HttpRequest } from '@smithy/protocol-http';
import { defaultProvider } from '@aws-sdk/credential-provider-node';

const SECRET_PREFIX = process.env.SECRET_PREFIX || 'lark-mcp/users';
const RUNTIME_ARN = process.env.RUNTIME_ARN!;
const AUTHORIZE_BASE = process.env.AUTHORIZE_BASE || '';
const REGION = process.env.AWS_REGION || 'us-west-2';
const TOKEN_BUFFER_SECONDS = 120;

const sm = new SecretsManagerClient({});

// In-memory token cache (per Lambda instance)
const tokenCache = new Map<string, { token: string; expiresAt: number }>();

interface LambdaEvent {
  body?: string;
  isBase64Encoded?: boolean;
  headers?: Record<string, string>;
  requestContext?: { authorizer?: { claims?: Record<string, string> } };
}

async function getUserToken(userId: string): Promise<string | null> {
  // Check cache first
  const cached = tokenCache.get(userId);
  if (cached && cached.expiresAt - Date.now() / 1000 > TOKEN_BUFFER_SECONDS) {
    return cached.token;
  }

  // Fetch from SM
  try {
    const resp = await sm.send(new GetSecretValueCommand({ SecretId: `${SECRET_PREFIX}/${userId}` }));
    const data = JSON.parse(resp.SecretString!);
    if (data.expires_at - Date.now() / 1000 > TOKEN_BUFFER_SECONDS) {
      tokenCache.set(userId, { token: data.access_token, expiresAt: data.expires_at });
      return data.access_token;
    }
    // Token expiring soon — return null to trigger re-auth
    // (EventBridge will refresh it; next request will succeed)
    return null;
  } catch { return null; }
}

export async function handler(event: LambdaEvent) {
  const claims = event.requestContext?.authorizer?.claims || {};
  const userId = claims.sub || claims['cognito:username'] || '';

  if (!userId) {
    return { statusCode: 401, headers: { 'Content-Type': 'application/json' }, body: '{"error":"unauthorized"}' };
  }

  const token = await getUserToken(userId);
  if (!token) {
    const authorizeUrl = AUTHORIZE_BASE ? `${AUTHORIZE_BASE}/authorize?user_id=${encodeURIComponent(userId)}` : '';
    return { statusCode: 403, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ error: 'feishu_not_authorized', authorize_url: authorizeUrl, user_id: userId }) };
  }

  const mcpPayload = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64').toString() : event.body || '';

  const request = new HttpRequest({
    method: 'POST',
    hostname: `bedrock-agentcore.${REGION}.amazonaws.com`,
    path: `/runtimes/${encodeURIComponent(RUNTIME_ARN)}/invocations`,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'X-User-Access-Token': token,
      'host': `bedrock-agentcore.${REGION}.amazonaws.com`,
    },
    body: mcpPayload,
  });

  const signer = new SignatureV4({
    credentials: defaultProvider(),
    region: REGION,
    service: 'bedrock-agentcore',
    sha256: Sha256,
  });

  const signed = await signer.sign(request);

  const resp = await fetch(`https://${signed.hostname}${signed.path}`, {
    method: 'POST',
    headers: signed.headers as Record<string, string>,
    body: mcpPayload,
  });

  const responseBody = await resp.text();
  return {
    statusCode: resp.status,
    headers: { 'Content-Type': resp.headers.get('content-type') || 'text/event-stream' },
    body: responseBody,
  };
}
