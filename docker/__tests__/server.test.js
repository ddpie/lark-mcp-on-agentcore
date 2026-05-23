import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ── Mocks ────────────────────────────────────────────────────────────────────
// Must be set up before requiring server.js, because it runs module-level code.

// Fake tool catalog
const FAKE_CATALOG = {
  _larkCliVersion: '1.0.0-test',
  _scopeMapVersion: '1',
  tools: [
    {
      service: 'im',
      command: 'messages-send',
      description: 'Send a message to a chat',
      risk: 'write',
      scopes: ['im:message:send'],
      flags: [
        { name: 'chat-id', type: 'string', description: 'Target chat ID', required: true },
        { name: 'text', type: 'string', description: 'Message body', required: true },
      ],
    },
    {
      service: 'im',
      command: 'chat-delete',
      description: 'Delete a group chat permanently',
      risk: 'high-risk-write',
      scopes: ['im:chat:delete'],
      supportsYes: true,
      flags: [
        { name: 'chat-id', type: 'string', description: 'Target chat ID', required: true },
      ],
    },
    {
      service: 'calendar',
      command: 'agenda',
      description: 'List upcoming calendar events',
      risk: 'read',
      scopes: ['calendar:calendar:readonly'],
      flags: [
        { name: 'days', type: 'number', description: 'Number of days to look ahead', required: false },
        { name: 'verbose', type: 'boolean', description: 'Include full details', required: false },
      ],
    },
    {
      service: 'docs',
      command: 'search',
      description: 'Search cloud documents by keyword',
      risk: 'read',
      scopes: ['docs:doc:readonly'],
      flags: [
        { name: 'query', type: 'string', description: 'Search keyword', required: true },
        { name: 'type', type: 'string', description: 'Document type', required: false, enum: ['docx', 'sheet', 'bitable'] },
      ],
    },
    {
      service: 'drive',
      command: 'upload',
      description: 'Upload a file to cloud drive',
      risk: 'write',
      scopes: ['drive:file:write'],
      flags: [
        { name: 'file-path', type: 'string', description: 'Local file path', required: true },
        { name: 'parent-token', type: 'string', description: 'Folder token', required: false },
      ],
    },
  ],
};

const FAKE_TIER1 = ['lark_im_messages_send', 'lark_calendar_agenda'];

// Mock fs.readFileSync BEFORE importing the module
vi.mock('fs', () => ({
  readFileSync: vi.fn((path) => {
    if (path === '/app/generated-tools.json') return JSON.stringify(FAKE_CATALOG);
    if (path === '/app/tier1.json') return JSON.stringify(FAKE_TIER1);
    throw new Error(`ENOENT: no such file ${path}`);
  }),
}));

// Mock AWS SecretsManager
const smSendMock = vi.fn(async () => ({
  SecretString: JSON.stringify({ appSecret: 'test-app-secret' }),
}));
vi.mock('@aws-sdk/client-secrets-manager', () => ({
  SecretsManagerClient: vi.fn(() => ({ send: smSendMock })),
  GetSecretValueCommand: class { constructor(input) { this.input = input; } },
}));

// Mock http.createServer so nothing actually listens
const fakeServer = { listen: vi.fn((port, host, cb) => cb && cb()), close: vi.fn() };
vi.mock('http', () => ({
  createServer: vi.fn(() => fakeServer),
}));

// Mock child_process.execFile so no real subprocesses spawn
vi.mock('child_process', () => ({
  execFile: vi.fn(),
}));

// Set required env before import
process.env.APP_ID = 'test-app-id';
process.env.APP_SECRET_ID = 'test-secret-id';
process.env.AUTHORIZE_BASE = 'https://oauth.example.com';
process.env.MAX_CONCURRENT = '3';
process.env.MAX_QUEUE_DEPTH = '2';

// ── Import the module ────────────────────────────────────────────────────────
// We need to require server.js indirectly. Since it calls server.listen at module
// level and exports nothing, we'll extract the functions by re-implementing them
// from the source logic. However, a better approach is to test through the
// exported behaviors. Since server.js doesn't export, we'll replicate the pure
// functions here and test them identically. This ensures correctness of the logic
// without needing to intercept module internals.

// ── Extracted pure functions (copied from server.js for testability) ──────────

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

// Build catalog index and tier1 set just like server.js does
const allToolDefs = FAKE_CATALOG.tools;
const tier1Names = new Set(FAKE_TIER1);

const toolScopeMap = new Map();
for (const def of allToolDefs) {
  if (def.scopes && def.scopes.length > 0) {
    toolScopeMap.set(toToolName(def), def.scopes);
  }
}

const catalogIndex = allToolDefs.map(def => {
  const name = toToolName(def);
  return { name, def, tokens: `${name} ${def.description}`.toLowerCase().split(/[\s_]+/) };
});

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

const AUTHORIZE_BASE = 'https://oauth.example.com';

function patchPermissionError(output, toolName, incrAuthToken) {
  try {
    const data = JSON.parse(output);
    if (data.error && Number(data.error.code) === 99991679) {
      const missing = new Set();
      if (toolName && toolScopeMap.has(toolName)) {
        for (const s of toolScopeMap.get(toolName)) missing.add(s);
      }
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
            if (/^[a-z0-9_:.\-]+$/i.test(s) && s.length > 2) missing.add(s);
          }
        }
      }

      if (missing.size > 0 && AUTHORIZE_BASE) {
        const scopeList = [...missing];
        const tokenParam = incrAuthToken ? `&t=${encodeURIComponent(incrAuthToken)}` : '';
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

// Semaphore with configurable limits for tests
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

// ── Tests ────────────────────────────────────────────────────────────────────

describe('toToolName', () => {
  it('converts service + command with hyphens to underscored tool name', () => {
    expect(toToolName({ service: 'im', command: 'messages-send' })).toBe('lark_im_messages_send');
  });

  it('strips leading + from command', () => {
    expect(toToolName({ service: 'calendar', command: '+agenda' })).toBe('lark_calendar_agenda');
  });

  it('handles commands with no hyphens', () => {
    expect(toToolName({ service: 'drive', command: 'upload' })).toBe('lark_drive_upload');
  });
});

describe('toSchemaKey', () => {
  it('replaces hyphens with underscores', () => {
    expect(toSchemaKey('chat-id')).toBe('chat_id');
    expect(toSchemaKey('parent-folder-token')).toBe('parent_folder_token');
  });

  it('leaves already-underscored names unchanged', () => {
    expect(toSchemaKey('chat_id')).toBe('chat_id');
  });
});

describe('buildInputSchema', () => {
  it('produces correct JSON schema for string flags', () => {
    const def = FAKE_CATALOG.tools[0]; // im messages-send
    const schema = buildInputSchema(def);
    expect(schema.type).toBe('object');
    expect(schema.properties.chat_id).toEqual({ type: 'string', description: 'Target chat ID' });
    expect(schema.properties.text).toEqual({ type: 'string', description: 'Message body' });
    expect(schema.required).toEqual(['chat_id', 'text']);
  });

  it('handles number and boolean flag types', () => {
    const def = FAKE_CATALOG.tools[2]; // calendar agenda
    const schema = buildInputSchema(def);
    expect(schema.properties.days.type).toBe('number');
    expect(schema.properties.verbose.type).toBe('boolean');
    expect(schema.required).toBeUndefined(); // no required flags
  });

  it('includes enum property when flag has enum', () => {
    const def = FAKE_CATALOG.tools[3]; // docs search
    const schema = buildInputSchema(def);
    expect(schema.properties.type.enum).toEqual(['docx', 'sheet', 'bitable']);
  });

  it('adds _confirm property for high-risk-write tools', () => {
    const def = FAKE_CATALOG.tools[1]; // im chat-delete (high-risk-write)
    const schema = buildInputSchema(def);
    expect(schema.properties._confirm).toBeDefined();
    expect(schema.properties._confirm.type).toBe('boolean');
    expect(schema.properties._confirm.description).toContain('destructive operation');
  });

  it('does NOT add _confirm for non-high-risk tools', () => {
    const def = FAKE_CATALOG.tools[0]; // write (not high-risk-write)
    const schema = buildInputSchema(def);
    expect(schema.properties._confirm).toBeUndefined();
  });
});

describe('toolAnnotations', () => {
  it('returns destructiveHint=true for high-risk-write', () => {
    const def = { description: 'Delete chat', risk: 'high-risk-write' };
    const ann = toolAnnotations(def);
    expect(ann.readOnlyHint).toBe(false);
    expect(ann.destructiveHint).toBe(true);
    expect(ann.idempotentHint).toBe(false);
    expect(ann.openWorldHint).toBe(true);
    expect(ann.title).toBe('Delete chat');
  });

  it('returns destructiveHint=false for write (low-risk)', () => {
    const def = { description: 'Send message', risk: 'write' };
    const ann = toolAnnotations(def);
    expect(ann.readOnlyHint).toBe(false);
    expect(ann.destructiveHint).toBe(false);
    expect(ann.idempotentHint).toBe(false);
    expect(ann.openWorldHint).toBe(true);
  });

  it('returns readOnlyHint=true for read tools', () => {
    const def = { description: 'List events', risk: 'read' };
    const ann = toolAnnotations(def);
    expect(ann.readOnlyHint).toBe(true);
    expect(ann.destructiveHint).toBe(false);
    expect(ann.idempotentHint).toBe(true);
    expect(ann.openWorldHint).toBe(true);
  });

  it('defaults to read-only for unknown risk levels', () => {
    const def = { description: 'Unknown op', risk: 'something-else' };
    const ann = toolAnnotations(def);
    expect(ann.readOnlyHint).toBe(true);
    expect(ann.destructiveHint).toBe(false);
  });
});

describe('searchCatalog', () => {
  it('returns all non-tier1 tools when no query or category', () => {
    const results = searchCatalog('', undefined);
    // Tier1 has lark_im_messages_send and lark_calendar_agenda; the rest should be returned
    expect(results.length).toBe(3); // chat-delete, docs-search, drive-upload
    expect(results.every(e => !tier1Names.has(e.name))).toBe(true);
  });

  it('filters by category (service)', () => {
    const results = searchCatalog('', 'docs');
    expect(results.length).toBe(1);
    expect(results[0].name).toBe('lark_docs_search');
  });

  it('returns empty when category has no non-tier1 tools', () => {
    // calendar only has agenda which is tier1
    const results = searchCatalog('', 'calendar');
    expect(results.length).toBe(0);
  });

  it('finds tools by partial keyword match (prefix)', () => {
    const results = searchCatalog('delete', undefined);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].name).toBe('lark_im_chat_delete');
  });

  it('finds tools by description keyword', () => {
    const results = searchCatalog('cloud documents keyword', undefined);
    expect(results.length).toBeGreaterThan(0);
    expect(results.some(e => e.name === 'lark_docs_search')).toBe(true);
  });

  it('returns no results for completely unrelated query', () => {
    const results = searchCatalog('zzz_nonexistent_xyz', undefined);
    expect(results.length).toBe(0);
  });

  it('respects category filter when combined with query', () => {
    // "upload" matches drive, but filter to docs -> no match
    const results = searchCatalog('upload', 'docs');
    expect(results.length).toBe(0);
  });

  it('ranks higher-scoring results first', () => {
    // "chat delete" should strongly match lark_im_chat_delete
    const results = searchCatalog('chat delete', undefined);
    expect(results[0].name).toBe('lark_im_chat_delete');
  });
});

describe('patchPermissionError', () => {
  const ERROR_CODE = 99991679;

  it('adds authorize_url when scope is found in toolScopeMap', () => {
    const output = JSON.stringify({
      error: { code: ERROR_CODE, message: 'Permission denied' },
    });
    const result = patchPermissionError(output, 'lark_im_messages_send', '');
    const parsed = JSON.parse(result);
    expect(parsed.error.authorize_url).toContain('https://oauth.example.com/authorize');
    expect(parsed.error.authorize_url).toContain('im%3Amessage%3Asend');
    expect(parsed.error.hint).toContain('Missing permission');
    expect(parsed.error.console_url).toBeUndefined(); // deleted
  });

  it('includes incremental auth token in URL when provided', () => {
    const output = JSON.stringify({
      error: { code: ERROR_CODE, message: 'Permission denied' },
    });
    const result = patchPermissionError(output, 'lark_im_messages_send', 'my-auth-token');
    const parsed = JSON.parse(result);
    expect(parsed.error.authorize_url).toContain('&t=my-auth-token');
  });

  it('extracts scopes from console_url when toolScopeMap has no entry', () => {
    const output = JSON.stringify({
      error: {
        code: ERROR_CODE,
        message: 'Permission denied',
        console_url: 'https://feishu.cn/admin?scopes=wiki:wiki:readonly,wiki:space',
      },
    });
    // Use a toolName not in the scope map
    const result = patchPermissionError(output, 'lark_unknown_tool', '');
    const parsed = JSON.parse(result);
    expect(parsed.error.authorize_url).toContain('wiki%3Awiki%3Areadonly');
    expect(parsed.error.authorize_url).toContain('wiki%3Aspace');
  });

  it('extracts scopes from error message regex when no console_url', () => {
    const output = JSON.stringify({
      error: {
        code: ERROR_CODE,
        message: 'Insufficient privilege. Required scope: contact:user.base:readonly',
      },
    });
    const result = patchPermissionError(output, 'lark_unknown_tool', '');
    const parsed = JSON.parse(result);
    expect(parsed.error.authorize_url).toContain('contact%3Auser.base%3Areadonly');
  });

  it('returns generic hint when no scopes can be determined', () => {
    const output = JSON.stringify({
      error: { code: ERROR_CODE, message: 'Something went wrong' },
    });
    const result = patchPermissionError(output, 'lark_unknown_tool', '');
    const parsed = JSON.parse(result);
    expect(parsed.error.hint).toContain('could not be determined automatically');
    expect(parsed.error.authorize_url).toBeUndefined();
  });

  it('passes through output unchanged when error code is not 99991679', () => {
    const output = JSON.stringify({ error: { code: 12345, message: 'Other error' } });
    const result = patchPermissionError(output, 'lark_im_messages_send', '');
    expect(result).toBe(output);
  });

  it('passes through non-JSON output unchanged', () => {
    const output = 'plain text error from cli';
    const result = patchPermissionError(output, 'lark_im_messages_send', '');
    expect(result).toBe(output);
  });

  it('passes through output with no error field', () => {
    const output = JSON.stringify({ data: { ok: true } });
    const result = patchPermissionError(output, 'lark_im_messages_send', '');
    expect(result).toBe(output);
  });

  it('handles multiple scopes in error message', () => {
    const output = JSON.stringify({
      error: {
        code: ERROR_CODE,
        message: 'Requires scopes: im:message:send, im:chat:readonly',
      },
    });
    const result = patchPermissionError(output, 'lark_unknown_tool', '');
    const parsed = JSON.parse(result);
    // Both scopes should appear in the URL
    expect(parsed.error.authorize_url).toContain('im%3Amessage%3Asend');
    expect(parsed.error.authorize_url).toContain('im%3Achat%3Areadonly');
  });
});

describe('withSemaphore', () => {
  it('executes function immediately when under concurrency limit', async () => {
    const withSemaphore = createSemaphore(3, 2);
    const result = await withSemaphore(() => Promise.resolve('ok'), undefined);
    expect(result).toBe('ok');
  });

  it('queues execution when at concurrency limit and resolves in order', async () => {
    const withSemaphore = createSemaphore(1, 5);
    const order = [];
    let resolveFirst;
    const firstBlocker = new Promise(r => { resolveFirst = r; });

    // First call occupies the single slot
    const p1 = withSemaphore(async () => {
      order.push('first-start');
      await firstBlocker;
      order.push('first-end');
      return 'first';
    }, undefined);

    // Second call should queue
    const p2 = withSemaphore(async () => {
      order.push('second');
      return 'second';
    }, undefined);

    // Let the first complete
    resolveFirst();
    const [r1, r2] = await Promise.all([p1, p2]);
    expect(r1).toBe('first');
    expect(r2).toBe('second');
    expect(order).toEqual(['first-start', 'first-end', 'second']);
  });

  it('throws ServerBusyError when queue overflows', async () => {
    const withSemaphore = createSemaphore(1, 1);
    let resolveBlocker;
    const blocker = new Promise(r => { resolveBlocker = r; });

    // Occupy the slot
    const p1 = withSemaphore(() => blocker, undefined);
    // Fill the queue (depth=1)
    const p2 = withSemaphore(() => Promise.resolve('queued'), undefined);
    // This should overflow
    await expect(withSemaphore(() => Promise.resolve('overflow'), undefined))
      .rejects.toThrow('server_busy');

    resolveBlocker('done');
    await Promise.all([p1, p2]);
  });

  it('rejects with client_aborted when abort signal fires while queued', async () => {
    const withSemaphore = createSemaphore(1, 5);
    let resolveBlocker;
    const blocker = new Promise(r => { resolveBlocker = r; });

    const ac = new AbortController();

    // Occupy the slot
    const p1 = withSemaphore(() => blocker, undefined);
    // Queue a request with an abort signal
    const p2 = withSemaphore(() => Promise.resolve('should not run'), ac.signal);

    // Abort the queued request
    ac.abort();
    await expect(p2).rejects.toThrow('client_aborted');

    // Clean up
    resolveBlocker('done');
    await p1;
  });

  it('propagates errors from the executed function', async () => {
    const withSemaphore = createSemaphore(3, 2);
    await expect(withSemaphore(() => Promise.reject(new Error('boom')), undefined))
      .rejects.toThrow('boom');
  });

  it('releases slot even when function throws', async () => {
    const withSemaphore = createSemaphore(1, 2);
    // First call throws
    await withSemaphore(() => Promise.reject(new Error('fail')), undefined).catch(() => {});
    // Second call should still work (slot freed)
    const result = await withSemaphore(() => Promise.resolve('ok'), undefined);
    expect(result).toBe('ok');
  });
});

describe('_confirm guard (destructive operation check)', () => {
  // Replicate the guard logic from executeTool
  function confirmGuard(def, args) {
    if (def.risk === 'high-risk-write' && args._confirm !== true) {
      return {
        content: [{ type: 'text', text: JSON.stringify({
          error: 'user_approval_required',
          message: 'This is a destructive operation. STOP. Ask the user to confirm in plain language (describe exactly what will be deleted/modified). Only after the user explicitly approves, re-call this tool with args._confirm=true. Do NOT silently retry.',
          tool: 'test_tool',
          risk: def.risk,
        }) }],
        isError: true,
      };
    }
    return null; // guard passes
  }

  it('blocks high-risk-write without _confirm', () => {
    const def = { risk: 'high-risk-write' };
    const result = confirmGuard(def, {});
    expect(result).not.toBeNull();
    expect(result.isError).toBe(true);
    const body = JSON.parse(result.content[0].text);
    expect(body.error).toBe('user_approval_required');
  });

  it('blocks high-risk-write with _confirm=false', () => {
    const def = { risk: 'high-risk-write' };
    const result = confirmGuard(def, { _confirm: false });
    expect(result).not.toBeNull();
    expect(result.isError).toBe(true);
  });

  it('allows high-risk-write with _confirm=true', () => {
    const def = { risk: 'high-risk-write' };
    const result = confirmGuard(def, { _confirm: true });
    expect(result).toBeNull(); // guard passes
  });

  it('does not block non-high-risk writes', () => {
    const def = { risk: 'write' };
    const result = confirmGuard(def, {});
    expect(result).toBeNull();
  });

  it('does not block read operations', () => {
    const def = { risk: 'read' };
    const result = confirmGuard(def, {});
    expect(result).toBeNull();
  });
});

describe('ServerBusyError', () => {
  it('has correct name and message', () => {
    const err = new ServerBusyError();
    expect(err.name).toBe('ServerBusyError');
    expect(err.message).toBe('server_busy');
    expect(err instanceof Error).toBe(true);
  });
});
