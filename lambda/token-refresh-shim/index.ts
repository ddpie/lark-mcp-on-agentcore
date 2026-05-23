import { createHmac, randomBytes, timingSafeEqual, createHash } from 'crypto';
import { SecretsManagerClient, GetSecretValueCommand, PutSecretValueCommand, CreateSecretCommand, ListSecretsCommand } from '@aws-sdk/client-secrets-manager';
import { storeCode, retrieveAndDeleteCode } from './dynamodb-codes';
import { log, hashUserId } from '../shared/log';

const FEISHU_TOKEN_URL = "https://open.feishu.cn/open-apis/authen/v1/oidc/access_token";
const FEISHU_REFRESH_URL = "https://open.feishu.cn/open-apis/authen/v1/oidc/refresh_access_token";
const CALLBACK_URL_ENV = process.env.CALLBACK_URL || '';
const SECRET_PREFIX = process.env.SECRET_PREFIX || "lark-mcp-on-agentcore/users";
const OPENID_PREFIX = process.env.OPENID_PREFIX || "lark-mcp-on-agentcore/openid-map";
const APP_SECRET_ID = process.env.APP_SECRET_ID || "lark-mcp-on-agentcore/feishu-app";
const STATE_SECRET = process.env.STATE_SECRET!;
const OAUTH_CLIENT_ID = process.env.OAUTH_CLIENT_ID || "lark-mcp-on-agentcore";
const OAUTH_CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET!;
const FEISHU_SCOPES = process.env.FEISHU_SCOPES || '';
const STATE_TTL_SECONDS = 300;
const MCP_TOKEN_TTL = 86400 * 30; // 30 days

const sm = new SecretsManagerClient({});
let appId = '';
let appSecret = '';

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

async function getUserInfo(userAccessToken: string): Promise<string> {
  // /authen/v1/user_info — name is returned by default (no extra scope needed).
  // Failures are non-fatal: success page falls back to userId.
  try {
    const resp = await fetch("https://open.feishu.cn/open-apis/authen/v1/user_info", {
      method: "GET",
      headers: { Authorization: `Bearer ${userAccessToken}` },
    });
    const data = await resp.json() as { code: number; data?: { name?: string } };
    return data.code === 0 ? (data.data?.name || '') : '';
  } catch { return ''; }
}

const PROJECT_TAGS = [{ Key: "project", Value: "lark-mcp-on-agentcore" }];

async function storeToken(userId: string, data: { access_token: string; refresh_token: string; expires_in: number }) {
  const secretId = `${SECRET_PREFIX}/${userId}`;
  const now = Math.floor(Date.now() / 1000);
  const value = JSON.stringify({
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_at: now + data.expires_in,
    issued_at: now,
  });
  try { await sm.send(new PutSecretValueCommand({ SecretId: secretId, SecretString: value })); }
  catch (e: any) { if (e.name === "ResourceNotFoundException") await sm.send(new CreateSecretCommand({ Name: secretId, SecretString: value, Tags: PROJECT_TAGS })); else throw e; }
}

interface StoredToken { access_token: string; refresh_token: string; expires_at: number; issued_at: number }

async function getToken(userId: string): Promise<StoredToken | null> {
  try {
    const resp = await sm.send(new GetSecretValueCommand({ SecretId: `${SECRET_PREFIX}/${userId}` }));
    return JSON.parse(resp.SecretString!);
  } catch { return null; }
}

// Probe SM writability for this user before consuming the single-use refresh_token.
// Re-writes current value (idempotent). If this fails, skip refresh — RT stays alive
// for the next EventBridge cycle when SM recovers.
async function preflightWritable(secretId: string, userId: string): Promise<boolean> {
  try {
    const current = await sm.send(new GetSecretValueCommand({ SecretId: secretId }));
    await sm.send(new PutSecretValueCommand({ SecretId: secretId, SecretString: current.SecretString! }));
    return true;
  } catch (e: any) {
    log('WARN', 'preflight_failed', { userIdHash: hashUserId(userId), error: e.message });
    return false;
  }
}

async function storeOpenIdMapping(openId: string, userId: string) {
  const secretId = `${OPENID_PREFIX}/${openId}`;
  const value = JSON.stringify({ userId });
  try {
    await sm.send(new PutSecretValueCommand({ SecretId: secretId, SecretString: value }));
  } catch (e: any) {
    if (e.name === "ResourceNotFoundException") {
      try {
        await sm.send(new CreateSecretCommand({ Name: secretId, SecretString: value, Tags: PROJECT_TAGS }));
      } catch (createErr: any) {
        log('ERROR', 'openid_create_failed', { openIdHash: hashUserId(openId), error: createErr.message, name: createErr.name });
      }
    } else {
      log('ERROR', 'openid_put_failed', { openIdHash: hashUserId(openId), error: e.message, name: e.name });
    }
  }
}

async function getOpenIdMapping(openId: string): Promise<string | null> {
  try {
    const resp = await sm.send(new GetSecretValueCommand({ SecretId: `${OPENID_PREFIX}/${openId}` }));
    return JSON.parse(resp.SecretString!).userId;
  } catch { return null; }
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
    const errors: Array<{ userIdHash: string; phase: string; error: string }> = [];
    let refreshed = 0, failed = 0, skipped = 0;

    for (const name of secrets) {
      const userId = name.replace(`${SECRET_PREFIX}/`, "");
      const stored = await getToken(userId);
      if (!stored) continue;

      // Adaptive window: refresh when remaining lifetime falls below 1/3 of total
      const totalTtl = stored.expires_at - stored.issued_at;
      const remaining = stored.expires_at - Date.now() / 1000;
      if (remaining > totalTtl / 3) continue;

      // Preflight: confirm SM is writable before consuming the refresh_token
      if (!(await preflightWritable(`${SECRET_PREFIX}/${userId}`, userId))) {
        skipped++;
        errors.push({ userIdHash: hashUserId(userId), phase: 'preflight', error: 'sm_not_writable' });
        continue;
      }

      let result;
      try {
        result = await refreshToken(stored.refresh_token, appToken);
      } catch (e: any) {
        failed++;
        errors.push({ userIdHash: hashUserId(userId), phase: 'feishu_call', error: e.message });
        continue;
      }
      if (result.code !== 0 || !result.data) {
        failed++;
        errors.push({ userIdHash: hashUserId(userId), phase: 'feishu_resp', error: `${result.code} ${result.msg}` });
        continue;
      }

      // Retry storeToken — preflight passed, but transient errors are still possible
      let storeOk = false;
      for (let i = 0; i < 3 && !storeOk; i++) {
        try {
          await storeToken(userId, result.data);
          storeOk = true;
        } catch (e: any) {
          if (i === 2) {
            // CRITICAL: refresh_token was consumed but new tokens were not persisted
            log('CRITICAL', 'store_token_lost', {
              userIdHash: hashUserId(userId),
              error: e.message,
              refresh_token_consumed: true,
            });
            errors.push({ userIdHash: hashUserId(userId), phase: 'store', error: e.message });
            failed++;
          } else {
            await new Promise(r => setTimeout(r, 1000 * Math.pow(2, i)));
          }
        }
      }
      if (storeOk) refreshed++;
    }

    // Emit a structured cycle summary so the RefreshFailed metric filter
    // ($.failed) actually has a log line to match. Lambda HTTP responses
    // are not surfaced to CloudWatch Logs.
    log('INFO', 'refresh_cycle', { refreshed, failed, skipped, total: secrets.length });

    return { statusCode: 200, body: JSON.stringify({ refreshed, failed, skipped, total: secrets.length, errors }) };
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
    // userId is ONLY accepted via the HMAC-signed `t=` token (incremental auth).
    // Raw `user_id` query param is rejected — accepting it would let an attacker
    // trick a victim into authorizing under an attacker-chosen id and overwrite
    // the victim's stored Feishu tokens (confused-deputy via legacy flow).
    let userId = '';
    const extraScopeRaw = (params.extra_scope || '').slice(0, 1000);
    const incrToken = params.t || '';

    // Verify signed incremental-auth token (carries the original userId)
    if (incrToken) {
      try {
        const decoded = Buffer.from(incrToken, 'base64url').toString();
        const lastColon = decoded.lastIndexOf(':');
        const secondLastColon = decoded.lastIndexOf(':', lastColon - 1);
        const sig = decoded.slice(lastColon + 1);
        const expiresAt = parseInt(decoded.slice(secondLastColon + 1, lastColon));
        const tokenUserId = decoded.slice(0, secondLastColon);
        if (Date.now() / 1000 <= expiresAt) {
          const expected = createHmac('sha256', STATE_SECRET).update(`${tokenUserId}:${expiresAt}`).digest('hex');
          const sigBuf = Buffer.from(sig, 'hex');
          const expBuf = Buffer.from(expected, 'hex');
          if (sigBuf.length === expBuf.length && timingSafeEqual(sigBuf, expBuf)) {
            userId = tokenUserId;
          }
        }
      } catch {}
    }
    const extraScope = /^[a-z0-9_:.\- ]+$/i.test(extraScopeRaw) ? extraScopeRaw : '';

    // Validate code_challenge_method if provided
    if (codeChallenge && codeChallengeMethod && codeChallengeMethod !== 'S256') {
      return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"only S256 code_challenge_method supported"}' };
    }

    // Standard OAuth flow (from Quick Desktop or any OAuth client)
    if (redirectUri) {
      // Validate redirect_uri using hostname comparison (not regex on the
      // full URL) — protocol-anchored regexes like /^https:\/\/[^/]+\.foo\.com/
      // can be bypassed by hosts like x.foo.com.attacker.com.
      let host = '';
      try {
        const u = new URL(redirectUri);
        if (u.protocol !== 'https:' && u.protocol !== 'http:') throw new Error('bad scheme');
        host = u.hostname;
      } catch {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"redirect_uri not a valid URL"}' };
      }
      const isQuickSight = host === 'quicksight.aws.amazon.com' || host.endsWith('.quicksight.aws.amazon.com');
      const isLocal = host === 'localhost' || host === '127.0.0.1';
      const customAllowed = ALLOWED_DOMAINS.some(d => host === d || host.endsWith(`.${d}`));
      if (!isQuickSight && !isLocal && !customAllowed) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"redirect_uri not allowed"}' };
      }
      // localhost / 127.0.0.1 must be plain HTTP only when explicitly local;
      // for any other host require HTTPS.
      if (!isLocal && new URL(redirectUri).protocol !== 'https:') {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"redirect_uri must use https"}' };
      }

      if (!codeChallenge) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"code_challenge required"}' };
      }

      // Encode redirect_uri and client_state into our internal state
      const statePayload = JSON.stringify({ r: redirectUri, s: clientState, c: codeChallenge });
      const state = signState(statePayload);
      const allScopes = [FEISHU_SCOPES, extraScope].filter(Boolean).join(' ');
      const scopeParam = allScopes ? `&scope=${encodeURIComponent(allScopes)}` : '';
      return {
        statusCode: 302,
        headers: { Location: `https://accounts.feishu.cn/open-apis/authen/v1/authorize?client_id=${appId}&response_type=code&redirect_uri=${encodeURIComponent(CALLBACK_URL)}&state=${state}${scopeParam}` },
      };
    }

    // Incremental-auth flow: requires a verified `t=` token (signed userId).
    // Without it, the only legitimate flow is standard OAuth (redirect_uri + PKCE).
    if (!userId) return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"missing redirect_uri or signed t= token"}' };
    const state = signState(JSON.stringify({ u: userId }));
    const incrScopes = extraScope ? extraScope : FEISHU_SCOPES;
    const scopeParamIncr = incrScopes ? `&scope=${encodeURIComponent(incrScopes)}` : '';
    return { statusCode: 302, headers: { Location: `https://accounts.feishu.cn/open-apis/authen/v1/authorize?client_id=${appId}&response_type=code&redirect_uri=${encodeURIComponent(CALLBACK_URL)}&state=${state}${scopeParamIncr}` } };
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
    if (result.code !== 0 || !result.data) {
      log('ERROR', 'feishu_exchange_failed', { code: result.code, msg: result.msg });
      return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "feishu_exchange_failed", detail: result.msg || result.code }) };
    }

    let stableUserId = '';
    if (stateData.u) {
      // Incremental-auth flow: userId came from a verified `t=` token.
      stableUserId = stateData.u;
    } else if (result.data.open_id) {
      // Standard OAuth flow: derive stable userId from Feishu open_id, with mapping reuse.
      const mapped = await getOpenIdMapping(result.data.open_id);
      stableUserId = mapped || result.data.open_id;
    } else {
      stableUserId = randomBytes(16).toString('hex');
    }
    await storeToken(stableUserId, result.data);
    if (result.data.open_id && stableUserId !== result.data.open_id) {
      await storeOpenIdMapping(result.data.open_id, stableUserId);
    }

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

    // Legacy flow: show success page + auto-redirect back to Quick Desktop via custom URL scheme.
    // Match lark-cli convention: "授权成功! 用户: {name}". Fall back to short userId.
    const userName = await getUserInfo(result.data.access_token);
    const displayName = userName || `${stableUserId.slice(0, 8)}…`;
    const successHtml = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>授权成功 / Authorized</title><style>body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;max-width:480px;margin:80px auto;padding:24px;text-align:center;color:#222}h2{color:#0a7d2c;margin-bottom:8px}.btn{display:inline-block;padding:10px 20px;margin-top:20px;background:#0a66c2;color:#fff;text-decoration:none;border-radius:6px;font-size:14px}p{color:#666;font-size:14px;line-height:1.5}.hint{color:#999;font-size:12px;margin-top:24px}</style></head><body><h2>✓ 授权成功 / Authorized</h2><p>${escapeHtml(displayName)} 已完成飞书授权。</p><a class="btn" href="awsquick://connector-refresh">返回 Amazon Quick Desktop</a><p class="hint">点击按钮回到 Quick Desktop 继续会话，或直接关闭此页面。<br>Click the button to return to Quick Desktop, or close this tab.</p></body></html>`;
    return { statusCode: 200, headers: { "Content-Type": "text/html; charset=utf-8" }, body: successHtml };
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
      if (!stored) {
        log('WARN', 'token_invalid_code');
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"invalid or expired code"}' };
      }

      if (Date.now() / 1000 > stored.expiresAt) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"code expired"}' };
      }

      // RFC 6749 §4.1.3 — if redirect_uri was used at /authorize, /token MUST
      // include it and it MUST match.
      if (stored.redirectUri) {
        if (!body.redirect_uri || body.redirect_uri !== stored.redirectUri) {
          log('WARN', 'token_redirect_uri_mismatch');
          return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"redirect_uri mismatch"}' };
        }
      }

      // Always verify PKCE
      if (!codeVerifier) {
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_request","error_description":"code_verifier required"}' };
      }
      const computedChallenge = createHash('sha256').update(codeVerifier).digest('base64url');
      if (computedChallenge !== stored.codeChallenge) {
        log('WARN', 'token_pkce_mismatch');
        return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_grant","error_description":"code_verifier mismatch"}' };
      }

      // Additionally verify client_secret if provided
      if (clientSecret && clientSecret !== OAUTH_CLIENT_SECRET) {
        log('WARN', 'token_bad_client_secret');
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
