#!/usr/bin/env node
// MCP Streamable HTTP server for AgentCore.
// Tiered tool architecture: 28 tier-1 + lark_discover + lark_invoke.
// Executes lark-cli commands with per-request user token injection.

const http = require('http');
const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');

const execFileAsync = promisify(execFile);

const PORT = 8000;
const APP_ID = process.env.APP_ID || '';
const APP_SECRET = process.env.APP_SECRET || '';
const BRAND = process.env.LARKSUITE_CLI_BRAND || 'feishu';
const AUTHORIZE_BASE = process.env.AUTHORIZE_BASE || '';

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
  return { type: 'object', properties, ...(required.length > 0 ? { required } : {}) };
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
      let missingScope = '';
      // Layer 2: check local scope mapping table first
      if (!missingScope && toolName && toolScopeMap.has(toolName)) {
        missingScope = toolScopeMap.get(toolName).join(' ');
      }
      // Layer 3: extract from lark-cli error response
      if (!missingScope && data.error.console_url) {
        try {
          const u = new URL(data.error.console_url);
          missingScope = u.searchParams.get('scopes') || '';
        } catch {}
      }
      if (!missingScope) {
        const m = (data.error.message || '').match(/required scope (\S+)/);
        if (m) missingScope = m[1].replace(/[,;.!)\]]+$/, '');
      }

      if (missingScope && AUTHORIZE_BASE) {
        const tokenParam = incrAuthToken ? `&t=${encodeURIComponent(incrAuthToken)}` : '';
        const authUrl = `${AUTHORIZE_BASE}/authorize?extra_scope=${encodeURIComponent(missingScope)}${tokenParam}`;
        data.error.hint = `Missing permission: ${missingScope}. Click to authorize: ${authUrl}`;
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

async function executeTool(def, args, userToken, toolName, incrAuthToken) {
  const cliArgs = [def.service, def.command];
  for (const flag of def.flags) {
    const key = toSchemaKey(flag.name);
    const value = args[key];
    if (value === undefined || value === null || value === '') continue;
    if (flag.type === 'boolean') { if (value) cliArgs.push(`--${flag.name}`); }
    else cliArgs.push(`--${flag.name}`, String(value));
  }
  if (def.risk === 'high-risk-write') cliArgs.push('--yes');

  const env = {
    ...process.env,
    NO_COLOR: '1',
    LARKSUITE_CLI_USER_ACCESS_TOKEN: userToken,
    LARKSUITE_CLI_APP_ID: APP_ID,
    LARKSUITE_CLI_APP_SECRET: APP_SECRET,
    LARKSUITE_CLI_BRAND: BRAND,
    LARKSUITE_CLI_DEFAULT_AS: 'user',
  };

  try {
    const { stdout } = await execFileAsync('lark-cli', cliArgs, { timeout: 60000, maxBuffer: 10 * 1024 * 1024, env });
    const output = stdout.trim() || '{"ok":true,"data":null}';
    return { content: [{ type: 'text', text: patchPermissionError(output, toolName, incrAuthToken) }] };
  } catch (err) {
    const message = err.stdout?.trim() || err.stderr?.trim() || err.message;
    return { content: [{ type: 'text', text: patchPermissionError(message, toolName, incrAuthToken) }], isError: true };
  }
}

function sseResponse(res, data) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  res.end(`event: message\ndata: ${JSON.stringify(data)}\n\n`);
}

const server = http.createServer((req, res) => {
  // Health check (AgentCore sends GET /ping)
  if (req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'Healthy', time_of_last_update: Math.floor(Date.now() / 1000) }));
    return;
  }

  if (req.method !== 'POST') {
    res.writeHead(405);
    res.end('');
    return;
  }

  const MAX_BODY = 1024 * 1024; // 1MB
  let body = '';
  let destroyed = false;
  req.on('data', chunk => {
    body += chunk;
    if (body.length > MAX_BODY) { destroyed = true; req.destroy(); res.writeHead(413); res.end(); return; }
  });
  req.on('end', () => { if (!destroyed) handleRequest(req, res, body); });
});

async function handleRequest(req, res, body) {
  let mcpReq;
  try { mcpReq = JSON.parse(body); } catch {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end('{"error":"invalid_json"}');
    return;
  }

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
        serverInfo: { name: 'lark-mcp-agentcore', version: '2.0.0' },
      },
    });
    return;
  }

  // tools/list
  if (mcpReq.method === 'tools/list') {
    const tools = [
      ...tier1Tools.map(t => ({ name: t.name, description: t.description, inputSchema: t.inputSchema })),
      DISCOVER_TOOL,
      INVOKE_TOOL,
    ];
    sseResponse(res, { jsonrpc: '2.0', id: mcpReq.id, result: { tools } });
    return;
  }

  // tools/call
  if (mcpReq.method === 'tools/call') {
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
      const result = await executeTool(entry.def, realArgs, userToken, realName, incrAuthToken);
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
      const result = await executeTool(tool._def, toolArgs, userToken, toolName, incrAuthToken);
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
  console.log(`lark-mcp-agentcore v2 listening on :${PORT} (${tier1Tools.length} tier1 + ${allToolDefs.length} discoverable)`);
});
