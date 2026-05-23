#!/usr/bin/env node
// MCP Streamable HTTP server for AgentCore.
// Tiered tool architecture: 28 tier-1 + lark_discover + lark_invoke.
// Executes lark-cli commands with per-request user token injection.

const http = require('http');
const fs = require('fs');
const { execFile } = require('child_process');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

process.on('uncaughtException', (err) => {
  console.error(JSON.stringify({ level: 'FATAL', event: 'uncaughtException', error: err.message, stack: err.stack }));
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  console.error(JSON.stringify({ level: 'ERROR', event: 'unhandledRejection', reason: String(reason) }));
});

// Track in-flight lark-cli child processes so SIGTERM can drain or kill them.
const activeChildren = new Set();

// Bounded concurrency for lark-cli child processes.
const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT || '10', 10);
const MAX_QUEUE_DEPTH = parseInt(process.env.MAX_QUEUE_DEPTH || '20', 10);
let activeProcesses = 0;
const queue = [];

class ServerBusyError extends Error {
  constructor() { super('server_busy'); this.name = 'ServerBusyError'; }
}

async function withSemaphore(fn, abortSignal) {
  if (activeProcesses >= MAX_CONCURRENT) {
    if (queue.length >= MAX_QUEUE_DEPTH) throw new ServerBusyError();
    await new Promise((resolve, reject) => {
      const entry = { resolve, reject };
      queue.push(entry);
      if (abortSignal) {
        abortSignal.addEventListener('abort', () => {
          const idx = queue.indexOf(entry);
          if (idx >= 0) { queue.splice(idx, 1); reject(new Error('client_aborted')); }
        }, { once: true });
      }
    });
  }
  activeProcesses++;
  try { return await fn(); }
  finally {
    activeProcesses--;
    const next = queue.shift();
    if (next) next.resolve();
  }
}

function runLarkCli(cliArgs, env, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = execFile('lark-cli', cliArgs, {
      timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024, env,
    }, (err, stdout, stderr) => {
      activeChildren.delete(child);
      if (err) reject(Object.assign(err, { stdout, stderr }));
      else resolve({ stdout, stderr });
    });
    activeChildren.add(child);
  });
}

const PORT = 8000;
const REGION = process.env.AWS_REGION || process.env.DEPLOY_REGION || 'us-west-2';
const APP_ID = process.env.APP_ID || '';
const APP_SECRET_ID = process.env.APP_SECRET_ID || 'lark-mcp-on-agentcore/feishu-app';
const BRAND = process.env.LARKSUITE_CLI_BRAND || 'feishu';
const AUTHORIZE_BASE = process.env.AUTHORIZE_BASE || '';

let APP_SECRET = '';
let appSecretLoaded = false;
let appSecretExpiry = 0;
const SECRET_CACHE_TTL = 30 * 60 * 1000; // 30 min
const sm = new SecretsManagerClient({ region: REGION });

async function loadAppSecret(maxRetries = 5) {
  if (appSecretLoaded && Date.now() < appSecretExpiry) return;
  for (let i = 0; i < maxRetries; i++) {
    try {
      const resp = await sm.send(new GetSecretValueCommand({ SecretId: APP_SECRET_ID }));
      APP_SECRET = JSON.parse(resp.SecretString).appSecret;
      appSecretLoaded = true;
      appSecretExpiry = Date.now() + SECRET_CACHE_TTL;
      console.log(JSON.stringify({ level: 'INFO', event: 'app_secret_loaded' }));
      return;
    } catch (e) {
      const wait = Math.min(500 * Math.pow(2, i), 8000);
      console.error(JSON.stringify({ level: 'WARN', event: 'app_secret_load_failed', attempt: i + 1, error: e.message, retry_in_ms: wait }));
      if (i < maxRetries - 1) await new Promise(r => setTimeout(r, wait));
      else throw e;
    }
  }
}

// Load tool catalog and tier1
const catalogRaw = JSON.parse(fs.readFileSync('/app/generated-tools.json', 'utf8'));
const allToolDefs = catalogRaw.tools || [];
const tier1Names = new Set(JSON.parse(fs.readFileSync('/app/tier1.json', 'utf8')));

console.log(`Tool catalog: ${allToolDefs.length} tools, Tier 1: ${tier1Names.size}`);

// Scope mapping: toolName -> required scopes (generated at build time)
const toolScopeMap = new Map();
for (const def of allToolDefs) {
  if (def.scopes && def.scopes.length > 0) {
    toolScopeMap.set(toToolName(def), def.scopes);
  }
}
console.log(`Scope map: ${toolScopeMap.size} tools (lark-cli ${catalogRaw._larkCliVersion}, scope-map ${catalogRaw._scopeMapVersion})`);

function toToolName(def) {
  const cmd = def.command.replace(/^\+/, '');
  return `lark_${def.service}_${cmd.replace(/-/g, '_')}`;
}

function toSchemaKey(flagName) { return flagName.replace(/-/g, '_'); }

function buildInputSchema(def) {
  const properties = {};
  const required = [];
  for (const flag of def.flags) {
    const key = toSchemaKey(flag.name);
    const prop = { description: flag.description };
    if (flag.type === 'boolean') prop.type = 'boolean';
    else if (flag.type === 'number') prop.type = 'number';
    else prop.type = 'string';
    if (flag.enum) prop.enum = flag.enum;
    properties[key] = prop;
    if (flag.required) required.push(key);
  }
  if (def.risk === 'high-risk-write') {
    properties._confirm = {
      type: 'boolean',
      description: 'Must be set to true to confirm this destructive operation. Ask the user first; do not set this without explicit user approval.',
    };
  }
  return { type: 'object', properties, ...(required.length > 0 ? { required } : {}) };
}

// MCP tool annotations (spec: 2025-03-26). Clients use these to render UI:
// destructive tools should prompt the user explicitly before invocation.
function toolAnnotations(def) {
  if (def.risk === 'high-risk-write') {
    return {
      title: def.description,
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    };
  }
  if (def.risk === 'write') {
    return {
      title: def.description,
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    };
  }
  return {
    title: def.description,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: true,
  };
}

// Build tier1 tool schemas
const tier1Tools = [];
for (const def of allToolDefs) {
  const name = toToolName(def);
  if (!tier1Names.has(name)) continue;
  tier1Tools.push({
    name,
    description: `[${def.risk}] ${def.description}`,
    inputSchema: buildInputSchema(def),
    _def: def,
  });
}
console.log(`Tier 1 matched: ${tier1Tools.length}/${tier1Names.size}`);

// Catalog index for discover
const catalogIndex = allToolDefs.map(def => {
  const name = toToolName(def);
  return { name, def, tokens: `${name} ${def.description}`.toLowerCase().split(/[\s_]+/) };
});

const DISCOVER_TOOL = {
  name: 'lark_discover',
  description: '[read] Discover lark-cli tools not in the high-frequency set. Use when registered tools cannot fulfill the need.',
  inputSchema: {
    type: 'object',
    anyOf: [{ required: ['query'] }, { required: ['category'] }],
    properties: {
      query: { type: 'string', description: 'Natural language or keyword, e.g. "create wiki space"' },
      category: { type: 'string', description: 'Filter by service: im, calendar, docs, base, sheets, drive, task, contact, wiki, mail, vc, minutes, okr, slides, whiteboard, markdown' },
    },
  },
};

const INVOKE_TOOL = {
  name: 'lark_invoke',
  description: '[read|write] Invoke a tool discovered via lark_discover. Pass exact tool_name and args.',
  inputSchema: {
    type: 'object',
    required: ['tool_name', 'args'],
    properties: {
      tool_name: { type: 'string', description: 'Tool name from lark_discover results' },
      args: { type: 'object', description: 'Tool arguments' },
    },
  },
};

function searchCatalog(query, category) {
  const tokens = query ? query.toLowerCase().split(/\s+/).filter(Boolean) : [];
  let candidates = catalogIndex.filter(e => !tier1Names.has(e.name));
  if (category) candidates = candidates.filter(e => e.def.service === category);
  if (tokens.length === 0) return candidates.slice(0, 20);

  const scored = [];
  for (const entry of candidates) {
    let score = 0;
    for (const tok of tokens) {
      if (entry.tokens.some(t => t.startsWith(tok) || tok.startsWith(t))) score++;
    }
    if (score > 0) scored.push({ entry, score });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, 20).map(s => s.entry);
}

function findByName(name) {
  return catalogIndex.find(e => e.name === name);
}

function patchPermissionError(output, toolName, incrAuthToken) {
  try {
    const data = JSON.parse(output);
    if (data.error && Number(data.error.code) === 99991679) {
      // Collect missing scopes as a Set, normalize to comma-separated for the URL.
      const missing = new Set();
      // Layer 2: check local scope mapping table first
      if (toolName && toolScopeMap.has(toolName)) {
        for (const s of toolScopeMap.get(toolName)) missing.add(s);
      }
      // Layer 3: extract from lark-cli error response
      if (missing.size === 0 && data.error.console_url) {
        try {
          const u = new URL(data.error.console_url);
          const raw = u.searchParams.get('scopes') || '';
          for (const s of raw.split(/[,\s]+/).filter(Boolean)) missing.add(s);
        } catch {}
      }
      if (missing.size === 0) {
        // Capture all scope tokens — Feishu may list multiple comma/space-separated.
        const matches = [...(data.error.message || '').matchAll(/scopes?[:\s]+([a-z0-9_:.\- ,]+)/gi)];
        for (const m of matches) {
          for (const s of m[1].split(/[,\s]+/)) {
            if (/^[a-z0-9_:.-]+$/i.test(s) && s.length > 2) missing.add(s);
          }
        }
      }

      if (missing.size > 0 && AUTHORIZE_BASE) {
        const scopeList = [...missing];
        const tokenParam = incrAuthToken ? `&t=${encodeURIComponent(incrAuthToken)}` : '';
        // OAuth Lambda expects comma-separated extra_scope (no spaces); each scope must be in allowlist.
        const authUrl = `${AUTHORIZE_BASE}/authorize?extra_scope=${encodeURIComponent(scopeList.join(','))}${tokenParam}`;
        data.error.hint = `Missing permission: ${scopeList.join(' ')}. Click to authorize: ${authUrl}`;
        data.error.authorize_url = authUrl;
      } else {
        data.error.hint = 'This tool requires a permission that could not be determined automatically. Please contact ddpie.flea@gmail.com for support.';
      }
      delete data.error.console_url;
      return JSON.stringify(data, null, 2);
    }
  } catch {}
  return output;
}

async function executeTool(def, args, userToken, toolName, incrAuthToken, abortSignal) {
  // High-risk writes (delete, etc.) require explicit user approval. Primary
  // defense is the destructiveHint annotation surfaced via tools/list — a
  // spec-compliant MCP client will pop a confirmation UI. _confirm is layered
  // defense for clients that ignore annotations.
  if (def.risk === 'high-risk-write' && args._confirm !== true) {
    return {
      content: [{ type: 'text', text: JSON.stringify({
        error: 'user_approval_required',
        message: 'This is a destructive operation. STOP. Ask the user to confirm in plain language (describe exactly what will be deleted/modified). Only after the user explicitly approves, re-call this tool with args._confirm=true. Do NOT silently retry.',
        tool: toolName,
        risk: def.risk,
      }) }],
      isError: true,
    };
  }

  const cliArgs = [def.service, def.command];
  for (const flag of def.flags) {
    const key = toSchemaKey(flag.name);
    const value = args[key];
    if (value === undefined || value === null || value === '') continue;
    if (flag.type === 'boolean') { if (value) cliArgs.push(`--${flag.name}`); }
    else cliArgs.push(`--${flag.name}`, String(value));
  }
  // lark-cli's --yes is per-command. Only inject it for commands that declare
  // it (recorded as supportsYes at build time); other high-risk-write commands
  // (e.g. delete-dimension) would treat --yes as an unknown flag and print usage.
  if (def.risk === 'high-risk-write' && def.supportsYes) cliArgs.push('--yes');

  const env = {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_PATH: process.env.NODE_PATH || '',
    LANG: process.env.LANG || 'en_US.UTF-8',
    NO_COLOR: '1',
    LARKSUITE_CLI_USER_ACCESS_TOKEN: userToken,
    LARKSUITE_CLI_APP_ID: APP_ID,
    LARKSUITE_CLI_APP_SECRET: APP_SECRET,
    LARKSUITE_CLI_BRAND: BRAND,
    LARKSUITE_CLI_DEFAULT_AS: 'user',
  };

  try {
    const { stdout } = await withSemaphore(() => runLarkCli(cliArgs, env, 60000), abortSignal);
    const output = stdout.trim() || '{"ok":true,"data":null}';
    return { content: [{ type: 'text', text: patchPermissionError(output, toolName, incrAuthToken) }] };
  } catch (err) {
    if (err instanceof ServerBusyError) {
      return { content: [{ type: 'text', text: '{"error":"server_busy","message":"Too many concurrent requests, retry shortly"}' }], isError: true };
    }
    if (err.message === 'client_aborted') {
      return { content: [{ type: 'text', text: '{"error":"client_aborted"}' }], isError: true };
    }
    const message = err.stdout?.trim() || err.stderr?.trim() || err.message;
    return { content: [{ type: 'text', text: patchPermissionError(message, toolName, incrAuthToken) }], isError: true };
  }
}

function sseResponse(res, data) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store' });
  res.end(`event: message\ndata: ${JSON.stringify(data)}\n\n`);
}

const server = http.createServer((req, res) => {
  // Health check (AgentCore sends GET /ping)
  if (req.method === 'GET') {
    if (!appSecretLoaded) {
      res.writeHead(503, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end('{"status":"Unhealthy","reason":"app_secret_not_loaded"}');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ status: 'Healthy', time_of_last_update: Math.floor(Date.now() / 1000) }));
    return;
  }

  if (req.method !== 'POST') {
    res.writeHead(405, { 'Cache-Control': 'no-store' });
    res.end('');
    return;
  }

  const MAX_BODY = 1024 * 1024; // 1MB
  let body = '';
  let destroyed = false;
  req.on('data', chunk => {
    if (destroyed) return;
    body += chunk;
    if (body.length > MAX_BODY) {
      destroyed = true;
      if (!res.headersSent) { res.writeHead(413, { 'Cache-Control': 'no-store' }); res.end(); }
      req.destroy();
    }
  });
  req.on('end', () => { if (!destroyed) handleRequest(req, res, body); });
});

async function handleRequest(req, res, body) {
  // Refresh cached app secret if TTL expired (non-blocking on cache hit)
  loadAppSecret(1).catch(() => {});

  let mcpReq;
  try { mcpReq = JSON.parse(body); } catch {
    res.writeHead(400, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end('{"error":"invalid_json"}');
    return;
  }

  // Propagate client-cancellation into the semaphore queue.
  const ac = new AbortController();
  req.on('close', () => ac.abort());

  // Extract user token and incremental-auth token from headers
  const userToken = req.headers['x-user-access-token'] || '';
  const incrAuthToken = req.headers['x-incr-auth-token'] || '';

  // initialize
  if (mcpReq.method === 'initialize') {
    sseResponse(res, {
      jsonrpc: '2.0', id: mcpReq.id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'lark-mcp-on-agentcore', version: '2.0.0' },
      },
    });
    return;
  }

  // tools/list — emit MCP annotations so spec-compliant clients (Quick Desktop,
  // Claude Desktop, etc.) render an explicit user-approval UI for destructive
  // tools instead of relying on the LLM to honor _confirm semantics.
  if (mcpReq.method === 'tools/list') {
    const tools = [
      ...tier1Tools.map(t => ({
        name: t.name,
        description: t.description,
        inputSchema: t.inputSchema,
        annotations: toolAnnotations(t._def),
      })),
      DISCOVER_TOOL,
      INVOKE_TOOL,
    ];
    sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { tools } });
    return;
  }

  // tools/call
  if (mcpReq.method === 'tools/call') {
    if (!appSecretLoaded) {
      sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { content: [{ type: 'text', text: '{"error":"server_initializing","message":"App secret not loaded yet, retry shortly"}' }], isError: true } });
      return;
    }
    const toolName = mcpReq.params?.name || '';
    const toolArgs = mcpReq.params?.arguments || {};

    // lark_discover
    if (toolName === 'lark_discover') {
      const results = searchCatalog(toolArgs.query, toolArgs.category);
      const output = results.map(e => ({
        name: e.name,
        description: `[${e.def.risk}] ${e.def.description}`,
        category: e.def.service,
        inputSchema: buildInputSchema(e.def),
        annotations: toolAnnotations(e.def),
      }));
      sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { content: [{ type: 'text', text: JSON.stringify({ tools: output }) }] } });
      return;
    }

    // lark_invoke
    if (toolName === 'lark_invoke') {
      const realName = toolArgs.tool_name;
      const realArgs = toolArgs.args || {};
      const entry = findByName(realName);
      if (!entry) {
        sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { content: [{ type: 'text', text: JSON.stringify({ error: 'unknown_tool', tool_name: realName }) }], isError: true } });
        return;
      }
      if (!userToken) {
        sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { content: [{ type: 'text', text: '{"error":"no user token"}' }], isError: true } });
        return;
      }
      const result = await executeTool(entry.def, realArgs, userToken, realName, incrAuthToken, ac.signal);
      sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result });
      return;
    }

    // Tier 1 direct call
    const tool = tier1Tools.find(t => t.name === toolName);
    if (tool) {
      if (!userToken) {
        sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { content: [{ type: 'text', text: '{"error":"no user token"}' }], isError: true } });
        return;
      }
      const result = await executeTool(tool._def, toolArgs, userToken, toolName, incrAuthToken, ac.signal);
      sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result });
      return;
    }

    sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, error: { code: -32601, message: `Unknown tool: ${toolName}` } });
    return;
  }

  // Other methods
  sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, error: { code: -32601, message: 'Method not found' } });
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`lark-mcp-on-agentcore listening on :${PORT} (${tier1Tools.length} tier1 + ${allToolDefs.length} discoverable)`);
  loadAppSecret().catch(e => {
    console.error(JSON.stringify({ level: 'CRITICAL', event: 'app_secret_load_giveup', error: e.message }));
    process.exit(1);
  });
});

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(JSON.stringify({ level: 'INFO', event: 'shutdown_start', signal, active_children: activeChildren.size }));

  server.close();
  await new Promise(r => setTimeout(r, 5000));

  for (const child of activeChildren) { try { child.kill('SIGTERM'); } catch {} }
  await new Promise(r => setTimeout(r, 2000));
  for (const child of activeChildren) { try { child.kill('SIGKILL'); } catch {} }

  console.log(JSON.stringify({ level: 'INFO', event: 'shutdown_complete' }));
  process.exit(0);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
