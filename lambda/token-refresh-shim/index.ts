import { createHmac, timingSafeEqual } from 'crypto';
import { SecretsManagerClient, GetSecretValueCommand, PutSecretValueCommand, CreateSecretCommand, ListSecretsCommand } from '@aws-sdk/client-secrets-manager';

const FEISHU_TOKEN_URL = "https://open.feishu.cn/open-apis/authen/v1/oidc/access_token";
const FEISHU_REFRESH_URL = "https://open.feishu.cn/open-apis/authen/v1/oidc/refresh_access_token";
const CALLBACK_URL = process.env.CALLBACK_URL!;
const SECRET_PREFIX = process.env.SECRET_PREFIX || "lark-mcp/users";
const APP_SECRET_ID = process.env.APP_SECRET_ID || "lark-mcp/feishu-app";
const STATE_SECRET = process.env.STATE_SECRET!;
const STATE_TTL_SECONDS = 300;

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
  path?: string;
  rawPath?: string;
  requestContext?: { http?: { method?: string; path?: string } };
  queryStringParameters?: Record<string, string>;
  source?: string;
}

function signState(userId: string): string {
  const ts = Math.floor(Date.now() / 1000);
  const payload = `${userId}:${ts}`;
  const sig = createHmac('sha256', STATE_SECRET).update(payload).digest('hex');
  return Buffer.from(`${payload}:${sig}`).toString('base64url');
}

function verifyState(state: string): { valid: boolean; userId: string } {
  try {
    const decoded = Buffer.from(state, 'base64url').toString();
    const lastColon = decoded.lastIndexOf(':');
    const secondLastColon = decoded.lastIndexOf(':', lastColon - 1);
    const sig = decoded.slice(lastColon + 1);
    const ts = parseInt(decoded.slice(secondLastColon + 1, lastColon));
    const userId = decoded.slice(0, secondLastColon);
    if (Date.now() / 1000 - ts > STATE_TTL_SECONDS) return { valid: false, userId: '' };
    const expected = createHmac('sha256', STATE_SECRET).update(`${userId}:${ts}`).digest('hex');
    const sigBuf = Buffer.from(sig, 'hex');
    const expBuf = Buffer.from(expected, 'hex');
    if (sigBuf.length !== expBuf.length || !timingSafeEqual(sigBuf, expBuf)) return { valid: false, userId: '' };
    return { valid: true, userId };
  } catch { return { valid: false, userId: '' }; }
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

export async function handler(event: LambdaEvent) {
  await loadAppCredentials();

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
  const params = event.queryStringParameters || {};

  if (path.includes("/authorize")) {
    const userId = params.user_id;
    if (!userId) return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: '{"error":"missing user_id"}' };
    const state = signState(userId);
    return { statusCode: 302, headers: { Location: `https://open.feishu.cn/open-apis/authen/v1/authorize?app_id=${appId}&redirect_uri=${encodeURIComponent(CALLBACK_URL)}&state=${state}` } };
  }

  if (path.includes("/callback")) {
    const { code, state } = params;
    if (!code || !state) return { statusCode: 400, body: "Missing code or state" };
    const { valid, userId } = verifyState(state);
    if (!valid) return { statusCode: 403, headers: { "Content-Type": "application/json" }, body: '{"error":"invalid_state"}' };
    const appToken = await getAppAccessToken();
    const result = await exchangeCode(code, appToken);
    if (result.code !== 0 || !result.data) return { statusCode: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: result.msg }) };
    await storeToken(userId, result.data);
    return { statusCode: 200, headers: { "Content-Type": "text/html; charset=utf-8" }, body: `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><h2>授权成功</h2><p>用户 ${escapeHtml(userId)} 已完成飞书授权，可以关闭此页面。</p></body></html>` };
  }


  return { statusCode: 404, body: '{"error":"not_found"}' };
}
