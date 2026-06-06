import { describe, it, expect } from 'vitest';
// Import the REAL implementations from server-lib.js (extracted from server.js
// so they can be tested without server.js's module-level side effects —
// fs reads of /app/* and server.listen). Same single-source-of-truth pattern as
// generate-tools-lib.js / skill-sections.js: server.js requires this module, so
// the two can never drift. Previously this file re-implemented every function
// inline and tested the COPY, which could never catch a regression in server.js.
import {
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
  createSingleFlight,
} from '../server-lib.js';

const FAKE_CATALOG = {
  tools: [
    {
      service: 'im', command: 'messages-send', description: 'Send a message to a chat',
      risk: 'write', scopes: ['im:message:send'],
      flags: [
        { name: 'chat-id', type: 'string', description: 'Target chat ID', required: true },
        { name: 'text', type: 'string', description: 'Message body', required: true },
      ],
    },
    {
      service: 'im', command: 'chat-delete', description: 'Delete a group chat permanently',
      risk: 'high-risk-write', scopes: ['im:chat:delete'], supportsYes: true,
      flags: [{ name: 'chat-id', type: 'string', description: 'Target chat ID', required: true }],
    },
    {
      service: 'calendar', command: 'agenda', description: 'List upcoming calendar events',
      risk: 'read', scopes: ['calendar:calendar:readonly'],
      flags: [
        { name: 'days', type: 'number', description: 'Number of days to look ahead', required: false },
        { name: 'verbose', type: 'boolean', description: 'Include full details', required: false },
      ],
    },
    {
      service: 'docs', command: 'search', description: 'Search cloud documents by keyword',
      risk: 'read', scopes: ['docs:doc:readonly'],
      flags: [
        { name: 'query', type: 'string', description: 'Search keyword', required: true },
        { name: 'type', type: 'string', description: 'Document type', required: false, enum: ['docx', 'sheet', 'bitable'] },
      ],
    },
    {
      service: 'drive', command: 'upload', description: 'Upload a file to cloud drive',
      risk: 'write', scopes: ['drive:file:write'],
      flags: [
        { name: 'file-path', type: 'string', description: 'Local file path', required: true },
        { name: 'parent-token', type: 'string', description: 'Folder token', required: false },
      ],
    },
  ],
};
const FAKE_TIER1 = new Set(['lark_im_messages_send', 'lark_calendar_agenda']);

// Build the shared state exactly as server.js does, via the same helpers.
const allToolDefs = FAKE_CATALOG.tools;
const toolScopeMap = buildToolScopeMap(allToolDefs);
const catalogIndex = buildCatalogIndex(allToolDefs);
const AUTHORIZE_BASE = 'https://oauth.example.com';

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
    const schema = buildInputSchema(FAKE_CATALOG.tools[0]);
    expect(schema.type).toBe('object');
    expect(schema.properties.chat_id).toEqual({ type: 'string', description: 'Target chat ID' });
    expect(schema.properties.text).toEqual({ type: 'string', description: 'Message body' });
    expect(schema.required).toEqual(['chat_id', 'text']);
  });
  it('handles number and boolean flag types', () => {
    const schema = buildInputSchema(FAKE_CATALOG.tools[2]);
    expect(schema.properties.days.type).toBe('number');
    expect(schema.properties.verbose.type).toBe('boolean');
    expect(schema.required).toBeUndefined();
  });
  it('includes enum property when flag has enum', () => {
    const schema = buildInputSchema(FAKE_CATALOG.tools[3]);
    expect(schema.properties.type.enum).toEqual(['docx', 'sheet', 'bitable']);
  });
  it('adds _confirm property for high-risk-write tools', () => {
    const schema = buildInputSchema(FAKE_CATALOG.tools[1]);
    expect(schema.properties._confirm).toBeDefined();
    expect(schema.properties._confirm.type).toBe('boolean');
    expect(schema.properties._confirm.description).toContain('destructive operation');
  });
  it('does NOT add _confirm for non-high-risk tools', () => {
    const schema = buildInputSchema(FAKE_CATALOG.tools[0]);
    expect(schema.properties._confirm).toBeUndefined();
  });
});

describe('toolAnnotations', () => {
  it('returns destructiveHint=true for high-risk-write', () => {
    const ann = toolAnnotations({ description: 'Delete chat', risk: 'high-risk-write' });
    expect(ann.readOnlyHint).toBe(false);
    expect(ann.destructiveHint).toBe(true);
    expect(ann.idempotentHint).toBe(false);
    expect(ann.openWorldHint).toBe(true);
    expect(ann.title).toBe('Delete chat');
  });
  it('returns destructiveHint=false for write (low-risk)', () => {
    const ann = toolAnnotations({ description: 'Send message', risk: 'write' });
    expect(ann.readOnlyHint).toBe(false);
    expect(ann.destructiveHint).toBe(false);
    expect(ann.idempotentHint).toBe(false);
    expect(ann.openWorldHint).toBe(true);
  });
  it('returns readOnlyHint=true for read tools', () => {
    const ann = toolAnnotations({ description: 'List events', risk: 'read' });
    expect(ann.readOnlyHint).toBe(true);
    expect(ann.destructiveHint).toBe(false);
    expect(ann.idempotentHint).toBe(true);
    expect(ann.openWorldHint).toBe(true);
  });
  it('defaults to read-only for unknown risk levels', () => {
    const ann = toolAnnotations({ description: 'Unknown op', risk: 'something-else' });
    expect(ann.readOnlyHint).toBe(true);
    expect(ann.destructiveHint).toBe(false);
  });
});

describe('searchCatalog', () => {
  const search = (q, cat) => searchCatalog(catalogIndex, FAKE_TIER1, q, cat);
  it('returns all non-tier1 tools when no query or category', () => {
    const results = search('', undefined);
    expect(results.length).toBe(3);
    expect(results.every(e => !FAKE_TIER1.has(e.name))).toBe(true);
  });
  it('filters by category (service)', () => {
    const results = search('', 'docs');
    expect(results.length).toBe(1);
    expect(results[0].name).toBe('lark_docs_search');
  });
  it('returns empty when category has no non-tier1 tools', () => {
    expect(search('', 'calendar').length).toBe(0);
  });
  it('finds tools by partial keyword match (prefix)', () => {
    const results = search('delete', undefined);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].name).toBe('lark_im_chat_delete');
  });
  it('finds tools by description keyword', () => {
    const results = search('cloud documents keyword', undefined);
    expect(results.some(e => e.name === 'lark_docs_search')).toBe(true);
  });
  it('returns no results for completely unrelated query', () => {
    expect(search('zzz_nonexistent_xyz', undefined).length).toBe(0);
  });
  it('respects category filter when combined with query', () => {
    expect(search('upload', 'docs').length).toBe(0);
  });
  it('ranks higher-scoring results first', () => {
    expect(search('chat delete', undefined)[0].name).toBe('lark_im_chat_delete');
  });
});

describe('findByName', () => {
  it('finds a catalog entry by its tool name', () => {
    expect(findByName(catalogIndex, 'lark_docs_search')?.name).toBe('lark_docs_search');
  });
  it('returns undefined for an unknown name', () => {
    expect(findByName(catalogIndex, 'lark_nope_nope')).toBeUndefined();
  });
});

describe('patchPermissionError', () => {
  const ERROR_CODE = 99991679;
  const patch = (output, toolName, tok) => patchPermissionError(toolScopeMap, AUTHORIZE_BASE, output, toolName, tok);

  it('adds authorize_url when scope is found in toolScopeMap', () => {
    const output = JSON.stringify({ error: { code: ERROR_CODE, message: 'Permission denied' } });
    const result = patch(output, 'lark_im_messages_send', '');
    expect(result).toContain('AUTHORIZATION REQUIRED');
    expect(result).toContain('https://oauth.example.com/authorize');
    expect(result).toContain('im%3Amessage%3Asend');
    expect(result).toContain('Do NOT retry');
    expect(result).not.toContain('console_url');
  });
  it('includes incremental auth token in URL when provided', () => {
    const output = JSON.stringify({ error: { code: ERROR_CODE, message: 'Permission denied' } });
    const result = patch(output, 'lark_im_messages_send', 'my-auth-token');
    expect(result).toContain('&t=my-auth-token');
  });
  it('extracts scopes from console_url when toolScopeMap has no entry', () => {
    const output = JSON.stringify({ error: { code: ERROR_CODE, message: 'Permission denied', console_url: 'https://feishu.cn/admin?scopes=wiki:wiki:readonly,wiki:space' } });
    const result = patch(output, 'lark_unknown_tool', '');
    expect(result).toContain('wiki%3Awiki%3Areadonly');
    expect(result).toContain('wiki%3Aspace');
  });
  it('extracts scopes from error message regex when no console_url', () => {
    const output = JSON.stringify({ error: { code: ERROR_CODE, message: 'Insufficient privilege. Required scope: contact:user.base:readonly' } });
    const result = patch(output, 'lark_unknown_tool', '');
    expect(result).toContain('contact%3Auser.base%3Areadonly');
  });
  it('returns generic hint when no scopes can be determined', () => {
    const output = JSON.stringify({ error: { code: ERROR_CODE, message: 'Something went wrong' } });
    const result = patch(output, 'lark_unknown_tool', '');
    const jsonPart = result.includes('---') ? result.split('---').pop().trim() : result;
    const parsed = JSON.parse(jsonPart);
    expect(parsed.error.hint).toContain('not automatically determined');
    expect(parsed.error.authorize_url).toBeUndefined();
  });
  it('passes through output unchanged when error code is not 99991679', () => {
    const output = JSON.stringify({ error: { code: 12345, message: 'Other error' } });
    expect(patch(output, 'lark_im_messages_send', '')).toBe(output);
  });
  it('passes through non-JSON output unchanged', () => {
    expect(patch('plain text error from cli', 'lark_im_messages_send', '')).toBe('plain text error from cli');
  });
  it('passes through output with no error field', () => {
    const output = JSON.stringify({ data: { ok: true } });
    expect(patch(output, 'lark_im_messages_send', '')).toBe(output);
  });
  it('handles multiple scopes in error message', () => {
    const output = JSON.stringify({ error: { code: ERROR_CODE, message: 'Requires scopes: im:message:send, im:chat:readonly' } });
    const result = patch(output, 'lark_unknown_tool', '');
    expect(result).toContain('im%3Amessage%3Asend');
    expect(result).toContain('im%3Achat%3Areadonly');
  });
});

describe('createSemaphore', () => {
  it('executes function immediately when under concurrency limit', async () => {
    const withSemaphore = createSemaphore(3, 2);
    expect(await withSemaphore(() => Promise.resolve('ok'), undefined)).toBe('ok');
  });
  it('queues execution when at concurrency limit and resolves in order', async () => {
    const withSemaphore = createSemaphore(1, 5);
    const order = [];
    let resolveFirst;
    const firstBlocker = new Promise(r => { resolveFirst = r; });
    const p1 = withSemaphore(async () => { order.push('first-start'); await firstBlocker; order.push('first-end'); return 'first'; }, undefined);
    const p2 = withSemaphore(async () => { order.push('second'); return 'second'; }, undefined);
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
    const p1 = withSemaphore(() => blocker, undefined);
    const p2 = withSemaphore(() => Promise.resolve('queued'), undefined);
    await expect(withSemaphore(() => Promise.resolve('overflow'), undefined)).rejects.toThrow('server_busy');
    resolveBlocker('done');
    await Promise.all([p1, p2]);
  });
  it('rejects with client_aborted when abort signal fires while queued', async () => {
    const withSemaphore = createSemaphore(1, 5);
    let resolveBlocker;
    const blocker = new Promise(r => { resolveBlocker = r; });
    const ac = new AbortController();
    const p1 = withSemaphore(() => blocker, undefined);
    const p2 = withSemaphore(() => Promise.resolve('should not run'), ac.signal);
    ac.abort();
    await expect(p2).rejects.toThrow('client_aborted');
    resolveBlocker('done');
    await p1;
  });
  it('propagates errors from the executed function', async () => {
    const withSemaphore = createSemaphore(3, 2);
    await expect(withSemaphore(() => Promise.reject(new Error('boom')), undefined)).rejects.toThrow('boom');
  });
  it('releases slot even when function throws', async () => {
    const withSemaphore = createSemaphore(1, 2);
    await withSemaphore(() => Promise.reject(new Error('fail')), undefined).catch(() => {});
    expect(await withSemaphore(() => Promise.resolve('ok'), undefined)).toBe('ok');
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

describe('createSingleFlight', () => {
  it('collapses concurrent calls into ONE underlying invocation', async () => {
    // Guards the loadAppSecret thundering-herd: at the TTL boundary, up to ~30
    // in-flight requests must NOT each fire a Secrets Manager call.
    let calls = 0;
    let release;
    const gate = new Promise(r => { release = r; });
    const sf = createSingleFlight(async () => { calls++; await gate; return calls; });

    const a = sf(); const b = sf(); const c = sf(); // three concurrent callers
    release();
    const [ra, rb, rc] = await Promise.all([a, b, c]);
    expect(calls).toBe(1);          // one underlying call
    expect([ra, rb, rc]).toEqual([1, 1, 1]); // all share the same result
  });

  it('allows a fresh call AFTER the in-flight one settles', async () => {
    let calls = 0;
    const sf = createSingleFlight(async () => { calls++; return calls; });
    expect(await sf()).toBe(1);
    expect(await sf()).toBe(2); // not deduped once the first settled
    expect(calls).toBe(2);
  });

  it('propagates rejection to all in-flight callers and clears for retry', async () => {
    let attempt = 0;
    const sf = createSingleFlight(async () => { attempt++; if (attempt === 1) throw new Error('boom'); return 'ok'; });
    const a = sf(); const b = sf();
    await expect(a).rejects.toThrow('boom');
    await expect(b).rejects.toThrow('boom'); // same failure shared
    // After the failed flight clears, a retry can succeed.
    expect(await sf()).toBe('ok');
    expect(attempt).toBe(2);
  });
});
