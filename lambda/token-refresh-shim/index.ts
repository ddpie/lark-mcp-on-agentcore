import { createHmac, randomBytes, timingSafeEqual, createHash } from 'crypto';
import { SecretsManagerClient, GetSecretValueCommand, PutSecretValueCommand, CreateSecretCommand, DeleteSecretCommand, ListSecretsCommand } from '@aws-sdk/client-secrets-manager';

const FEISHU_TOKEN_URL = "https://open.feishu.cn/open-apis/authen/v1/oidc/access_token";
const FEISHU_REFRESH_URL = "https://open.feishu.cn/open-apis/authen/v1/oidc/refresh_access_token";
const CALLBACK_URL_ENV = process.env.CALLBACK_URL || '';
const SECRET_PREFIX = process.env.SECRET_PREFIX || "lark-mcp/users";
const APP_SECRET_ID = process.env.APP_SECRET_ID || "lark-mcp/feishu-app";
const STATE_SECRET = process.env.STATE_SECRET!;
const OAUTH_CLIENT_ID = process.env.OAUTH_CLIENT_ID || "lark-mcp";
const OAUTH_CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET!;
const STATE_TTL_SECONDS = 300;
const MCP_TOKEN_TTL = 86400 * 30; // 30 days

const sm = new SecretsManagerClient({});
let appId = '';
let appSecret = '';

async function storeCode(code: string, data: { userId: string; codeChallenge: string; redirectUri: string; expiresAt: number }) {
  await sm.send(new CreateSecretCommand({ Name: `lark-mcp/codes/${code}`, SecretString: JSON.stringify(data) }));
}

async function retrieveAndDeleteCode(code: string): Promise<{ userId: string; codeChallenge: string; redirectUri: string; expiresAt: number } | null> {
  try {
    const resp = await sm.send(new GetSecretValueCommand({ SecretId: `lark-mcp/codes/${code}` }));
    const data = JSON.parse(resp.SecretString!);
    // Delete immediately (single-use)
    await sm.send(new DeleteSecretCommand({ SecretId: `lark-mcp/codes/${code}`, ForceDeleteWithoutRecovery: true }));
    return data;
  } catch { return null; }
}

async function loadAppCredentials() {
  if (appId) return;
  const resp = await sm.send(new GetSecretValueCommand({ SecretId: APP_SECRET_ID }));
  const data = JSON.parse(resp.SecretString!);
  appId = data.appId;
  appSecret = data.appSecret;
}

interface LambdaEvent {
  body?: string;
  isBase64Encoded?: boolean;
  headers?: Record<string, string>;
  httpMethod?: string;
  path?: string;
  rawPath?: string;
  requestContext?: { http?: { method?: string; path?: string }; domainName?: string };
  queryStringParameters?: Record<string, string>;
  source?: string;
}

const ALLOWED_DOMAINS = (process.env.ALLOWED_DOMAINS || '').split(',').map(d => d.trim()).filter(Boolean);

function getCallbackUrl(event: LambdaEvent): string {
  if (CALLBACK_URL_ENV && CALLBACK_URL_ENV !== 'SET_AFTER_DEPLOY') return CALLBACK_URL_ENV;
  const host = event.headers?.host || event.headers?.Host || event.requestContext?.domainName || '';
  if (!host) return '';
  if (/\.(cloudfront\.net|amazonaws\.com)$/.test(host)) return `https://${host}/callback`;
  if (ALLOWED_DOMAINS.some(d => host === d || host.endsWith(`.${d}`))) return `https://${host}/callback`;
  return '';
}

function signState(payload: string): string {
  const ts = Math.floor(Date.now() / 1000);
  const payloadB64 = Buffer.from(payload).toString('base64url');
  const full = `${payloadB64}.${ts}`;
  const sig = createHmac('sha256', STATE_SECRET).update(full).digest('hex');
  return `${full}.${sig}`;
}

function verifyState(state: string): { valid: boolean; payload: string } {
  try {
    const parts = state.split('.');
    if (parts.length !== 3) return { valid: false, payload: '' };
    const [payloadB64, tsStr, sig] = parts;
    const ts = parseInt(tsStr);
    if (Date.now() / 1000 - ts > STATE_TTL_SECONDS) return { valid: false, payload: '' };
    const full = `${payloadB64}.${tsStr}`;
    const expected = createHmac('sha256', STATE_SECRET).update(full).digest('hex');
    const sigBuf = Buffer.from(sig, 'hex');
    const expBuf = Buffer.from(expected, 'hex');
    if (sigBuf.length !== expBuf.length || !timingSafeEqual(sigBuf, expBuf)) return { valid: false, payload: '' };
    const payload = Buffer.from(payloadB64, 'base64url').toString();
    return { valid: true, payload };
  } catch { return { valid: false, payload: '' }; }
}

function generateMcpToken(userId: string): string {
  const expiresAt = Math.floor(Date.now() / 1000) + MCP_TOKEN_TTL;
  const payload = `${userId}:${expiresAt}`;
  const sig = createHmac('sha256', STATE_SECRET).update(payload).digest('hex');
  return Buffer.from(`${payload}:${sig}`).toString('base64url');
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

async function getAppAccessToken(): Promise<string> {
  await loadAppCredentials();
  const resp = await fetch("https://open.feishu.cn/open-apis/auth/v3/app_access_token/internal", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ app_id: appId, app_secret: appSecret }),
  });
  return ((await resp.json()) as { app_access_token: string }).app_access_token;
}

async function exchangeCode(code: string, appToken: string) {
  const resp = await fetch(FEISHU_TOKEN_URL, {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${appToken}` },
    body: JSON.stringify({ grant_type: "authorization_code", code }),
  });
  return resp.json() as Promise<{ code: number; msg: string; data?: { access_token: string; refresh_token: string; expires_in: number; open_id: string } }>;
}

async function refreshToken(rt: string, appToken: string) {
  const resp = await fetch(FEISHU_REFRESH_URL, {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${appToken}` },
    body: JSON.stringify({ grant_type: "refresh_token", refresh_token: rt }),
  });
  return resp.json() as Promise<{ code: number; msg: string; data?: { access_token: string; refresh_token: string; expires_in: number } }>;
}

async function storeToken(userId: string, data: { access_token: string; refresh_token: string; expires_in: number }) {
  const secretId = `${SECRET_PREFIX}/${userId}`;
  const value = JSON.stringify({ access_token: data.access_token, refresh_token: data.refresh_token, expires_at: Math.floor(Date.now() / 1000) + data.expires_in });
  try { await sm.send(new PutSecretValueCommand({ SecretId: secretId, SecretString: value })); }
  catch (e: any) { if (e.name === "ResourceNotFoundException") await sm.send(new CreateSecretCommand({ Name: secretId, SecretString: value })); else throw e; }
}

async function getToken(userId: string): Promise<{ access_token: string; refresh_token: string; expires_at: number } | null> {
  try { const resp = await sm.send(new GetSecretValueCommand({ SecretId: `${SECRET_PREFIX}/${userId}` })); return JSON.parse(resp.SecretString!); }
  catch { return null; }
}

async function listAllUserSecrets(): Promise<string[]> {
  const names: string[] = [];
  let nextToken: string | undefined;
  do {
    const resp = await sm.send(new ListSecretsCommand({ Filters: [{ Key: "name", Values: [SECRET_PREFIX] }], NextToken: nextToken }));
    for (const s of resp.SecretList || []) if (s.Name) names.push(s.Name);
    nextToken = resp.NextToken;
  } while (nextToken);
  return names;
}

function parseBody(event: LambdaEvent): Record<string, string> {
  const raw = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64').toString() : event.body || '';
  const params: Record<string, string> = {};
  for (const pair of raw.split('&')) {
    const [k, v] = pair.split('=');
    if (k) params[decodeURIComponent(k)] = decodeURIComponent(v || '');
  }
  return params;
}

export async function handler(event: LambdaEvent) {
  await loadAppCredentials();

  // EventBridge scheduled refresh
  if (event.source === "aws.events") {
    const appToken = await getAppAccessToken();
    const secrets = await listAllUserSecrets();
    let refreshed = 0, failed = 0;
    for (const name of secrets) {
      const userId = name.replace(`${SECRET_PREFIX}/`, "");
      const stored = await getToken(userId);
      if (!stored || stored.expires_at - Date.now() / 1000 > 1800) continue;
      const result = await refreshToken(stored.refresh_token, appToken);
      if (result.code === 0 && result.data) { await storeToken(userId, result.data); refreshed++; }
      else { failed++; }
    }
    return { statusCode: 200, body: JSON.stringify({ refreshed, failed, total: secrets.length }) };
  }

  const path = event.path || event.requestContext?.http?.path || event.rawPath || "/";
  const method = event.httpMethod || event.requestContext?.http?.method || "GET";
  const params = event.queryStringParameters || {};
  const CALLBACK_URL = getCallbackUrl(event);

  // OAuth 2.0 Authorization Server Metadata (RFC 8414)
  if (path.includes("/.well-known/oauth-authorization-server")) {
    const baseUrl = CALLBACK_URL.replace(/\/callback$/, '');
    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" },
      body: JSON.stringify({
        issuer: baseUrl,
        authorization_endpoint: `${baseUrl}/authorize`,
        token_endpoint: `${baseUrl}/token`,
        response_types_supported: ["code"],
        grant_types_supported: ["authorization_code"],
        code_challenge_methods_supported: ["S256"],
        token_endpoint_auth_methods_supported: ["none", "client_secret_post"],
      }),
    };
  }

  // /authorize — OAuth 2.0 authorization endpoint
  if (path.includes("/authorize")) {
    const redirectUri = params.redirect_uri || '';
    const clientState = params.state || '';
    const codeChallenge = params.code_challenge || '';
    const codeChallengeMethod = params.code_challenge_method || '';
    const userId = params.user_id || '';

    // Validate code_challenge_method if provided
    if (codeChallenge && codeChallengeMethod && codeChallengeMethod !== 'S256') {
      return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"only S256 code_challenge_method supported"}' };
    }

    // Standard OAuth flow (from Quick Desktop or any OAuth client)
    if (redirectUri) {
      // Validate redirect_uri against allowlist
      const allowedPatterns = [
        /^https:\/\/[^/]+\.quicksight\.aws\.amazon\.com/,
        /^https:\/\/[^/]+\.amazonaws\.com/,
        /^https?:\/\/localhost(:\d+)?/,
        /^https?:\/\/127\.0\.0\.1(:\d+)?/,
      ];
      const customAllowed = ALLOWED_DOMAINS.some(d => {
        try { return new URL(redirectUri).hostname === d || new URL(redirectUri).hostname.endsWith(`.${d}`); } catch { return false; }
      });
      if (!customAllowed && !allowedPatterns.some(p => p.test(redirectUri))) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"redirect_uri not allowed"}' };
      }

      if (!codeChallenge) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"code_challenge required"}' };
      }

      // Encode redirect_uri and client_state into our internal state
      const statePayload = JSON.stringify({ r: redirectUri, s: clientState, c: codeChallenge });
      const state = signState(statePayload);
      return {
        statusCode: 302,
        headers: { Location: `https://open.feishu.cn/open-apis/authen/v1/authorize?app_id=${appId}&redirect_uri=${encodeURIComponent(CALLBACK_URL)}&state=${state}` },
      };
    }

    // Legacy flow (user_id based, for manual authorization)
    if (!userId) return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"missing redirect_uri or user_id"}' };
    const state = signState(JSON.stringify({ u: userId }));
    return { statusCode: 302, headers: { Location: `https://open.feishu.cn/open-apis/authen/v1/authorize?app_id=${appId}&redirect_uri=${encodeURIComponent(CALLBACK_URL)}&state=${state}` } };
  }

  // /callback — Feishu redirects here after user consent
  if (path.includes("/callback")) {
    const { code, state } = params;
    if (!code || !state) return { statusCode: 400, body: "Missing code or state" };
    const { valid, payload } = verifyState(state);
    if (!valid) return { statusCode: 403, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_state"}' };

    let stateData: { r?: string; s?: string; c?: string; u?: string };
    try { stateData = JSON.parse(payload); } catch { return { statusCode: 400, body: "invalid state payload" }; }

    const appToken = await getAppAccessToken();
    const result = await exchangeCode(code, appToken);
    if (result.code !== 0 || !result.data) return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "feishu_exchange_failed", detail: result.msg || result.code }) };

    const stableUserId = result.data.open_id || stateData.u || randomBytes(16).toString('hex');
    await storeToken(stableUserId, result.data);

    // Standard OAuth flow: generate auth code and redirect back to client
    if (stateData.r) {
      const authCode = randomBytes(32).toString('hex');
      await storeCode(authCode, {
        userId: stableUserId,
        codeChallenge: stateData.c || '',
        redirectUri: stateData.r,
        expiresAt: Date.now() / 1000 + 120,
      });
      const sep = stateData.r.includes('?') ? '&' : '?';
      const redirectBack = `${stateData.r}${sep}code=${authCode}${stateData.s ? `&state=${encodeURIComponent(stateData.s)}` : ''}`;
      return { statusCode: 302, headers: { Location: redirectBack } };
    }

    // Legacy flow: show success page
    return { statusCode: 200, headers: { "Content-Type": "text/html; charset=utf-8" }, body: `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><h2>授权成功</h2><p>用户 ${escapeHtml(stableUserId)} 已完成飞书授权，可以关闭此页面。</p></body></html>` };
  }

  // /token — OAuth 2.0 token endpoint
  if (path.includes("/token") && method === "POST") {
    const body = parseBody(event);
    const grantType = body.grant_type;

    if (grantType === "authorization_code") {
      const authCode = body.code || '';
      const codeVerifier = body.code_verifier || '';
      const clientSecret = body.client_secret || '';

      const stored = await retrieveAndDeleteCode(authCode);
      if (!stored) return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"invalid or expired code"}' };

      if (Date.now() / 1000 > stored.expiresAt) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"code expired"}' };
      }

      // Verify redirect_uri matches what was used at authorization time
      if (stored.redirectUri && body.redirect_uri && body.redirect_uri !== stored.redirectUri) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"redirect_uri mismatch"}' };
      }

      // Always verify PKCE
      if (!codeVerifier) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"code_verifier required"}' };
      }
      const computedChallenge = createHash('sha256').update(codeVerifier).digest('base64url');
      if (computedChallenge !== stored.codeChallenge) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"code_verifier mismatch"}' };
      }

      // Additionally verify client_secret if provided
      if (clientSecret && clientSecret !== OAUTH_CLIENT_SECRET) {
        return { statusCode: 401, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_client","error_description":"bad client credentials"}' };
      }

      const mcpToken = generateMcpToken(stored.userId);
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
        body: JSON.stringify({ access_token: mcpToken, token_type: "Bearer", expires_in: MCP_TOKEN_TTL }),
      };
    }

    return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"unsupported_grant_type"}' };
  }

  if (path.includes("/token") && method === "GET") {
    return { statusCode: 405, headers: { "Content-Type": "application/json" }, body: '{"error":"method_not_allowed"}' };
  }

  return { statusCode: 404, body: '{"error":"not_found"}' };
}
