import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createHmac, createHash, randomBytes } from 'crypto';
import { mockClient } from './mock-client';

// Required env vars must be set BEFORE the handler module is imported.
process.env.STATE_SECRET = 'test-state-secret';
process.env.OAUTH_CLIENT_SECRET = 'test-client-secret';
process.env.CODE_TABLE = 'test-table';
process.env.CALLBACK_URL = 'https://test.cloudfront.net/callback';
process.env.SECRET_PREFIX = 'lark-mcp-on-agentcore/users';
process.env.OPENID_PREFIX = 'lark-mcp-on-agentcore/openid-map';
process.env.APP_SECRET_ID = 'lark-mcp-on-agentcore/feishu-app';
process.env.OAUTH_CLIENT_ID = 'lark-mcp-on-agentcore';
process.env.FEISHU_SCOPES = 'im:message contact:user.base:readonly';

vi.mock('@aws-sdk/client-secrets-manager', () => mockClient.secretsManager);
vi.mock('@aws-sdk/lib-dynamodb', () => mockClient.dynamodb);
vi.mock('@aws-sdk/client-dynamodb', () => ({ DynamoDBClient: vi.fn(() => ({})) }));

const STATE_SECRET = process.env.STATE_SECRET!;
const CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET!;

// Helpers ---------------------------------------------------------------------

function signMcpToken(userId: string, expiresAt: number, secret = STATE_SECRET): string {
  const sig = createHmac('sha256', secret).update(`${userId}:${expiresAt}`).digest('hex');
  return Buffer.from(`${userId}:${expiresAt}:${sig}`).toString('base64url');
}

function signIncrToken(userId: string, expiresAt: number, secret = STATE_SECRET): string {
  return signMcpToken(userId, expiresAt, secret);
}

function pkce() {
  const verifier = randomBytes(32).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge };
}

async function call(event: any) {
  // Reset module so module-level appId/appSecret cache is fresh per test.
  vi.resetModules();
  const { handler } = await import('../index');
  return handler(event);
}

// Seed app credentials before every test so loadAppCredentials() succeeds.
beforeEach(() => {
  mockClient.reset();
  mockClient.secretsManager.__set(
    'lark-mcp-on-agentcore/feishu-app',
    JSON.stringify({ appId: 'cli_test', appSecret: 'app-secret' })
  );
});
afterEach(() => { vi.restoreAllMocks(); });

// =============================================================================
// /authorize
// =============================================================================

describe('/authorize — extra_scope validation', () => {
  it('accepts comma-separated scopes that are in the allowlist', async () => {
    const { challenge } = pkce();
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: {
        redirect_uri: 'https://quicksight.aws.amazon.com/cb',
        code_challenge: challenge,
        code_challenge_method: 'S256',
        extra_scope: 'im:chat:read,im:message',
      },
    });
    expect(result.statusCode).toBe(302);
  });

  it('rejects space-separated extra_scope (would have been accepted in old regex)', async () => {
    const { challenge } = pkce();
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: {
        redirect_uri: 'https://quicksight.aws.amazon.com/cb',
        code_challenge: challenge,
        code_challenge_method: 'S256',
        extra_scope: 'im:chat:read im:message',
      },
    });
    expect(result.statusCode).toBe(400);
    expect(result.body).toContain('extra_scope contains unknown or malformed scope');
  });

  it('rejects scope that is syntactically valid but not in allowlist', async () => {
    const { challenge } = pkce();
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: {
        redirect_uri: 'https://quicksight.aws.amazon.com/cb',
        code_challenge: challenge,
        code_challenge_method: 'S256',
        extra_scope: 'fake:nonexistent:scope',
      },
    });
    expect(result.statusCode).toBe(400);
  });
});

describe('/authorize — redirect_uri allowlist', () => {
  it('rejects hostname spoofing (attacker subdomain trick)', async () => {
    const { challenge } = pkce();
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: {
        redirect_uri: 'https://quicksight.aws.amazon.com.attacker.com/cb',
        code_challenge: challenge,
        code_challenge_method: 'S256',
      },
    });
    expect(result.statusCode).toBe(400);
    expect(result.body).toContain('redirect_uri not allowed');
  });

  it('rejects http for non-localhost hosts', async () => {
    const { challenge } = pkce();
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: {
        redirect_uri: 'http://quicksight.aws.amazon.com/cb',
        code_challenge: challenge,
        code_challenge_method: 'S256',
      },
    });
    expect(result.statusCode).toBe(400);
    expect(result.body).toContain('must use https');
  });

  it('accepts localhost over http (RFC 8252 native-app flow)', async () => {
    const { challenge } = pkce();
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: {
        redirect_uri: 'http://localhost:31337/cb',
        code_challenge: challenge,
        code_challenge_method: 'S256',
      },
    });
    expect(result.statusCode).toBe(302);
  });
});

describe('/authorize — t= incremental-auth token', () => {
  it('accepts a valid signed t= token', async () => {
    const exp = Math.floor(Date.now() / 1000) + 300;
    const t = signIncrToken('ou_test', exp);
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: { t },
    });
    expect(result.statusCode).toBe(302);
    // location should embed Feishu state derived from u=ou_test (not the legacy user_id form)
    expect(result.headers?.Location).toContain('accounts.feishu.cn');
  });

  it('rejects a t= token signed with a different secret (tamper)', async () => {
    const exp = Math.floor(Date.now() / 1000) + 300;
    const t = signIncrToken('ou_attacker', exp, 'wrong-secret');
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: { t },
    });
    expect(result.statusCode).toBe(400);
  });

  it('rejects expired t= token', async () => {
    const exp = Math.floor(Date.now() / 1000) - 10;
    const t = signIncrToken('ou_test', exp);
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: { t },
    });
    expect(result.statusCode).toBe(400);
  });

  it('rejects legacy ?user_id= path (PR25 regression guard)', async () => {
    const result = await call({
      path: '/authorize',
      httpMethod: 'GET',
      queryStringParameters: { user_id: 'ou_attacker' },
    });
    expect(result.statusCode).toBe(400);
  });
});

// =============================================================================
// /token
// =============================================================================

describe('/token — client_secret enforcement', () => {
  function tokenBody(extra: Record<string, string> = {}) {
    const params = new URLSearchParams({ grant_type: 'authorization_code', code: 'fake', code_verifier: 'v', redirect_uri: 'https://x.example', ...extra });
    return params.toString();
  }

  it('rejects request with no client_secret (401, before any DB lookup)', async () => {
    const result = await call({
      path: '/token',
      httpMethod: 'POST',
      body: tokenBody(),
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
    });
    expect(result.statusCode).toBe(401);
    expect(result.body).toContain('client_secret required');
    // Code DB must not be touched — wrong secret should not burn the code.
    expect(mockClient.dynamodb.__hasCode('any')).toBe(false);
  });

  it('rejects wrong client_secret (401)', async () => {
    const result = await call({
      path: '/token',
      httpMethod: 'POST',
      body: tokenBody({ client_secret: 'WRONG' }),
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
    });
    expect(result.statusCode).toBe(401);
    expect(result.body).toContain('bad client credentials');
  });

  it('client_secret check runs BEFORE retrieveAndDeleteCode (does not consume code)', async () => {
    // Seed a real code; it should still be present after the failed exchange.
    mockClient.dynamodb.__seedCode({
      code: 'real-code', userId: 'u1', codeChallenge: 'cc', redirectUri: 'https://x.example', expiresAt: Date.now() / 1000 + 60,
    });
    await call({
      path: '/token',
      httpMethod: 'POST',
      body: tokenBody({ code: 'real-code', client_secret: 'WRONG' }),
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
    });
    expect(mockClient.dynamodb.__hasCode('real-code')).toBe(true);
  });

  it('issues an MCP token when client_secret + PKCE both correct', async () => {
    const { verifier, challenge } = pkce();
    mockClient.dynamodb.__seedCode({
      code: 'real-code', userId: 'ou_user', codeChallenge: challenge, redirectUri: 'https://x.example', expiresAt: Date.now() / 1000 + 60,
    });
    const result = await call({
      path: '/token',
      httpMethod: 'POST',
      body: new URLSearchParams({ grant_type: 'authorization_code', code: 'real-code', code_verifier: verifier, redirect_uri: 'https://x.example', client_secret: CLIENT_SECRET }).toString(),
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
    });
    expect(result.statusCode).toBe(200);
    const body = JSON.parse(result.body!);
    expect(body.access_token).toBeTruthy();
    expect(body.token_type).toBe('Bearer');
    // Now the code IS consumed.
    expect(mockClient.dynamodb.__hasCode('real-code')).toBe(false);
  });
});

describe('/token — PKCE', () => {
  it('rejects when code_verifier does not match the challenge', async () => {
    const { challenge } = pkce();
    mockClient.dynamodb.__seedCode({
      code: 'real-code', userId: 'u1', codeChallenge: challenge, redirectUri: 'https://x.example', expiresAt: Date.now() / 1000 + 60,
    });
    const result = await call({
      path: '/token',
      httpMethod: 'POST',
      body: new URLSearchParams({ grant_type: 'authorization_code', code: 'real-code', code_verifier: 'wrong-verifier', redirect_uri: 'https://x.example', client_secret: CLIENT_SECRET }).toString(),
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
    });
    expect(result.statusCode).toBe(400);
    expect(result.body).toContain('code_verifier mismatch');
  });
});

// =============================================================================
// /callback (state verification)
// =============================================================================

describe('/callback — state verification', () => {
  it('rejects a state with a tampered signature (403)', async () => {
    const result = await call({
      path: '/callback',
      httpMethod: 'GET',
      queryStringParameters: { code: 'fake', state: 'aaaa.123.bb' },
    });
    expect(result.statusCode).toBe(403);
  });

  it('rejects expired state', async () => {
    // craft an old-but-correctly-signed state and verify it's refused
    const old = Math.floor(Date.now() / 1000) - 99999;
    const payload = Buffer.from(JSON.stringify({ r: 'https://x.example' })).toString('base64url');
    const full = `${payload}.${old}`;
    const sig = createHmac('sha256', STATE_SECRET).update(full).digest('hex');
    const result = await call({
      path: '/callback',
      httpMethod: 'GET',
      queryStringParameters: { code: 'fake', state: `${full}.${sig}` },
    });
    expect(result.statusCode).toBe(403);
  });
});

// =============================================================================
// MCP token verification (for parity with what the middleware does)
// =============================================================================

describe('MCP token shape', () => {
  it('a freshly issued MCP token verifies under the same secret', async () => {
    const { verifier, challenge } = pkce();
    mockClient.dynamodb.__seedCode({
      code: 'c2', userId: 'ou_z', codeChallenge: challenge, redirectUri: 'https://x.example', expiresAt: Date.now() / 1000 + 60,
    });
    const r = await call({
      path: '/token',
      httpMethod: 'POST',
      body: new URLSearchParams({ grant_type: 'authorization_code', code: 'c2', code_verifier: verifier, redirect_uri: 'https://x.example', client_secret: CLIENT_SECRET }).toString(),
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
    });
    const token = JSON.parse(r.body!).access_token;
    const decoded = Buffer.from(token, 'base64url').toString();
    const lastColon = decoded.lastIndexOf(':');
    const secondLastColon = decoded.lastIndexOf(':', lastColon - 1);
    const userId = decoded.slice(0, secondLastColon);
    const expiresAt = parseInt(decoded.slice(secondLastColon + 1, lastColon));
    const sig = decoded.slice(lastColon + 1);
    const expected = createHmac('sha256', STATE_SECRET).update(`${userId}:${expiresAt}`).digest('hex');
    expect(sig).toBe(expected);
    expect(userId).toBe('ou_z');
    expect(expiresAt).toBeGreaterThan(Date.now() / 1000);
  });
});

// =============================================================================
// /callback (full Feishu exchange path)
// =============================================================================

// Build a state string the way signState() inside index.ts would.
function buildState(payloadObj: any): string {
  const payloadB64 = Buffer.from(JSON.stringify(payloadObj)).toString('base64url');
  const ts = Math.floor(Date.now() / 1000);
  const full = `${payloadB64}.${ts}`;
  const sig = createHmac('sha256', STATE_SECRET).update(full).digest('hex');
  return `${full}.${sig}`;
}

// Mock the three Feishu endpoints + user_info. Returns the recorded calls so
// tests can assert on what was sent.
function mockFeishu(opts: {
  exchange?: { code?: number; msg?: string; data?: any };
  userInfo?: { code?: number; data?: { name?: string } };
  userInfoFails?: boolean;
} = {}) {
  const calls: { url: string; init?: any }[] = [];
  vi.spyOn(global, 'fetch').mockImplementation(async (input: any, init: any) => {
    const url = typeof input === 'string' ? input : input.url;
    calls.push({ url, init });
    if (url.includes('app_access_token')) {
      return new Response(JSON.stringify({ app_access_token: 'app-token' }));
    }
    if (url.includes('oidc/access_token')) {
      const body = opts.exchange ?? {
        code: 0, msg: 'ok',
        data: { access_token: 'feishu-tok', refresh_token: 'rt', expires_in: 7200, open_id: 'ou_real_user' },
      };
      return new Response(JSON.stringify(body));
    }
    if (url.includes('user_info')) {
      if (opts.userInfoFails) throw new Error('network');
      const body = opts.userInfo ?? { code: 0, data: { name: '张三' } };
      return new Response(JSON.stringify(body));
    }
    return new Response('{}');
  });
  return { calls };
}

describe('/callback — full Feishu exchange path', () => {
  it('standard OAuth flow: stores token, generates auth code, 302 to client', async () => {
    mockFeishu();
    const state = buildState({ r: 'https://quicksight.aws.amazon.com/cb', s: 'client-state-xyz', c: 'pkce-challenge' });
    const r = await call({
      path: '/callback',
      httpMethod: 'GET',
      queryStringParameters: { code: 'feishu-code', state },
    });
    expect(r.statusCode).toBe(302);
    const loc = r.headers!.Location;
    expect(loc).toMatch(/^https:\/\/quicksight\.aws\.amazon\.com\/cb\?code=[a-f0-9]{64}&state=client-state-xyz$/);
  });

  it('returns 400 when Feishu exchange fails (code != 0)', async () => {
    mockFeishu({ exchange: { code: 99, msg: 'bad code', data: undefined } });
    const state = buildState({ r: 'https://quicksight.aws.amazon.com/cb', s: 's', c: 'c' });
    const r = await call({
      path: '/callback',
      httpMethod: 'GET',
      queryStringParameters: { code: 'fake', state },
    });
    expect(r.statusCode).toBe(400);
    expect(r.body).toContain('feishu_exchange_failed');
  });

  it('legacy flow (no redirect_uri, signed t= → state {u}) renders success HTML with the user name', async () => {
    mockFeishu();
    const state = buildState({ u: 'ou_real_user' });
    const r = await call({
      path: '/callback',
      httpMethod: 'GET',
      queryStringParameters: { code: 'feishu-code', state },
    });
    expect(r.statusCode).toBe(200);
    expect(r.headers?.['Content-Type']).toContain('text/html');
    expect(r.body).toContain('授权成功');
    // Name from /authen/v1/user_info should be rendered, not the hex userId
    expect(r.body).toContain('张三');
  });

  it('falls back to userId prefix when /authen/v1/user_info fails', async () => {
    mockFeishu({ userInfoFails: true });
    const state = buildState({ u: 'ou_abcdefghijklmnop' });
    const r = await call({
      path: '/callback',
      httpMethod: 'GET',
      queryStringParameters: { code: 'feishu-code', state },
    });
    expect(r.statusCode).toBe(200);
    // Should show short prefix, not full userId
    expect(r.body).toContain('ou_abcde');
    expect(r.body).not.toContain('ou_abcdefghijklmnop 已完成');
  });
});
