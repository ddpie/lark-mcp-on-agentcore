const http = require('http');
const { spawn } = require('child_process');

const PORT = 8000;
const LARK_PORT = 8001;
const AUTHORIZE_BASE = process.env.AUTHORIZE_BASE || '';
const SECRET_PREFIX = process.env.SECRET_PREFIX || 'lark-mcp/users';
const AWS_REGION = process.env.AWS_REGION || 'us-west-2';

// Start lark-mcp
const args = ['mcp', '-a', process.env.APP_ID, '-s', process.env.APP_SECRET,
  '-u', process.env.UAT_PLACEHOLDER || 'placeholder',
  '-m', 'streamable', '--host', '127.0.0.1', '-p', String(LARK_PORT)];
if (process.env.LARK_MCP_EXTRA_ARGS)
  args.push(...process.env.LARK_MCP_EXTRA_ARGS.split(' ').filter(Boolean));

const child = spawn('lark-mcp', args, { stdio: 'inherit' });
child.on('exit', (code) => process.exit(code || 1));

// Readiness tracking
let backendReady = false;
function checkBackend() {
  const req = http.request({ hostname: '127.0.0.1', port: LARK_PORT, path: '/mcp', method: 'GET', timeout: 2000 }, () => {
    backendReady = true;
    console.log('lark-mcp ready');
  });
  req.on('error', () => setTimeout(checkBackend, 300));
  req.on('timeout', () => { req.destroy(); setTimeout(checkBackend, 300); });
  req.end();
}
setTimeout(checkBackend, 500);

// Lazy SM client
let sm = null;
let GetSecretValueCommand = null;
let smReady = false;

(async () => {
  try {
    const sdk = require('@aws-sdk/client-secrets-manager');
    sm = new sdk.SecretsManagerClient({ region: AWS_REGION });
    GetSecretValueCommand = sdk.GetSecretValueCommand;
    smReady = true;
  } catch (e) {
    console.error('SM SDK not available:', e.message);
  }
})();

async function getUserToken(userId) {
  if (!smReady || !sm) return null;
  try {
    const resp = await sm.send(new GetSecretValueCommand({ SecretId: `${SECRET_PREFIX}/${userId}` }));
    const data = JSON.parse(resp.SecretString);
    if (data.expires_at - Date.now() / 1000 > 120) return data.access_token;
    return null;
  } catch { return null; }
}

const proxy = http.createServer(async (req, res) => {
  // Readiness: if backend not ready, return 503 for health checks
  if (!backendReady) {
    res.writeHead(503, { 'Content-Type': 'application/json' });
    res.end('{"jsonrpc":"2.0","error":{"code":-32000,"message":"starting"},"id":null}');
    return;
  }

  const headers = { ...req.headers };
  let path = req.url;

  const externalToken = headers['x-user-access-token'];
  if (externalToken) {
    headers['authorization'] = `Bearer ${externalToken}`;
    delete headers['x-user-access-token'];
    if (!path.includes('tokenMode='))
      path += (path.includes('?') ? '&' : '?') + 'tokenMode=user_access_token';
  } else {
    const userId = headers['x-amzn-bedrock-agentcore-runtime-user-id'] || headers['x-runtime-user-id'];
    if (userId) {
      const token = await getUserToken(userId);
      if (token) {
        headers['authorization'] = `Bearer ${token}`;
        if (!path.includes('tokenMode='))
          path += (path.includes('?') ? '&' : '?') + 'tokenMode=user_access_token';
      } else if (AUTHORIZE_BASE) {
        const authorizeUrl = `${AUTHORIZE_BASE}/authorize?user_id=${encodeURIComponent(userId)}`;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          jsonrpc: '2.0',
          error: { code: -32001, message: `User not authorized. Visit: ${authorizeUrl}`, data: { authorize_url: authorizeUrl, user_id: userId } },
          id: null
        }));
        return;
      }
    }
  }

  const proxyReq = http.request(
    { hostname: '127.0.0.1', port: LARK_PORT, path, method: req.method, headers },
    (proxyRes) => { res.writeHead(proxyRes.statusCode, proxyRes.headers); proxyRes.pipe(res); }
  );
  proxyReq.on('error', (e) => {
    res.writeHead(502);
    res.end(JSON.stringify({ jsonrpc: '2.0', error: { code: -32000, message: String(e.message).slice(0, 100) }, id: null }));
  });
  req.pipe(proxyReq);
});

proxy.listen(PORT, '0.0.0.0', () => console.log(`Proxy :${PORT} → lark-mcp :${LARK_PORT}`));
