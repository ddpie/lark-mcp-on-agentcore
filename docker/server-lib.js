// Pure, side-effect-free helpers for the MCP server.
//
// Extracted from server.js so they can be unit-tested directly: server.js runs
// module-level code on require (reads /app/*.json, scans /app/skills, calls
// server.listen), so it cannot be imported in tests. Keeping these functions
// here is the single source of truth — server.js requires this module, the
// tests import this module, and the two can never drift. (Same pattern as
// generate-tools-lib.js and skill-sections.js.)
//
// Functions that depend on per-process state (the catalog index, the scope map,
// the OAuth authorize base) take that state as parameters rather than closing
// over module globals, so they stay pure and testable.

const PERMISSION_ERROR_CODE = 99991679;

class ServerBusyError extends Error {
  constructor() { super('server_busy'); this.name = 'ServerBusyError'; }
}

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
    return { title: def.description, readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true };
  }
  if (def.risk === 'write') {
    return { title: def.description, readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true };
  }
  return { title: def.description, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true };
}

// toolName -> required scopes (only for tools that declare scopes).
function buildToolScopeMap(toolDefs) {
  const map = new Map();
  for (const def of toolDefs) {
    if (def.scopes && def.scopes.length > 0) map.set(toToolName(def), def.scopes);
  }
  return map;
}

// Searchable catalog index: each entry carries its tool name, the def, and a
// lowercased token list (name + description) for prefix matching.
function buildCatalogIndex(toolDefs) {
  return toolDefs.map(def => {
    const name = toToolName(def);
    return { name, def, tokens: `${name} ${def.description}`.toLowerCase().split(/[\s_]+/) };
  });
}

function searchCatalog(catalogIndex, tier1Names, query, category) {
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

function findByName(catalogIndex, name) {
  return catalogIndex.find(e => e.name === name);
}

// Rewrite a lark-cli permission-denied error into an actionable hint with an
// incremental-auth URL. Layered scope discovery: local scope map → console_url
// query param → scope tokens parsed out of the error message.
function patchPermissionError(toolScopeMap, authorizeBase, output, toolName, incrAuthToken) {
  try {
    const data = JSON.parse(output);
    if (data.error && Number(data.error.code) === PERMISSION_ERROR_CODE) {
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
        const matches = [...(data.error.message || '').matchAll(/scopes?[:\s]+([a-z0-9_:.\- ,]+)/gi)];
        for (const m of matches) {
          for (const s of m[1].split(/[,\s]+/)) {
            if (/^[a-z0-9_:.-]+$/i.test(s) && s.length > 2) missing.add(s);
          }
        }
      }

      if (missing.size > 0 && authorizeBase) {
        const scopeList = [...missing];
        const tokenParam = incrAuthToken ? `&t=${encodeURIComponent(incrAuthToken)}` : '';
        const authUrl = `${authorizeBase}/authorize?extra_scope=${encodeURIComponent(scopeList.join(','))}${tokenParam}`;
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

// Bounded-concurrency gate. Returns a withSemaphore(fn, abortSignal) function
// holding its own counters, so each server process (or test) gets an isolated
// semaphore. Queued callers past maxConcurrent wait for a slot; past
// maxQueueDepth they get ServerBusyError. A queued caller whose abortSignal
// fires is spliced out and rejected with client_aborted.
function createSemaphore(maxConcurrent, maxQueueDepth) {
  let activeProcesses = 0;
  const queue = [];

  return async function withSemaphore(fn, abortSignal) {
    if (activeProcesses >= maxConcurrent) {
      if (queue.length >= maxQueueDepth) throw new ServerBusyError();
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
  };
}

module.exports = {
  PERMISSION_ERROR_CODE,
  ServerBusyError,
  toToolName,
  toSchemaKey,
  buildInputSchema,
  toolAnnotations,
  buildToolScopeMap,
  buildCatalogIndex,
  searchCatalog,
  findByName,
  patchPermissionError,
  createSemaphore,
};
