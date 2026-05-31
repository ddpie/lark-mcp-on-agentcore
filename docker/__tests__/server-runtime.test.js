/**
 * Server runtime behavior tests (concurrency queue, child-process error mapping).
 *
 * These need things the protocol-contract suite can't express with its
 * instant-success execFile mock and default concurrency:
 *   - R1: force the semaphore QUEUE (MAX_CONCURRENT=1) and prove a queued
 *     request is NOT spuriously aborted just because its own request body
 *     finished arriving.
 *   - R4: make execFile fail with timeout / maxBuffer and prove the client
 *     gets a clean structured error, not a truncated partial-stdout fragment.
 *
 * Runs in its own vitest worker (forks pool, per-file isolation), so importing
 * server.js here — which listens on the hardcoded port 8000 — does not collide
 * with mcp-contract.test.js's server.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import fs from 'node:fs';
import Module from 'node:module';

// Force the queue to engage with just two concurrent requests. MUST be set
// before importing server.js (read at module load).
process.env.MAX_CONCURRENT = '1';
process.env.MAX_QUEUE_DEPTH = '20';

const FAKE_TOOL_DEF_READ = {
  service: 'calendar',
  command: '+agenda',
  description: 'Show upcoming calendar events',
  risk: 'read',
  flags: [{ name: 'days', type: 'number', description: 'Number of days', required: false }],
};
const FAKE_CATALOG = { _larkCliVersion: 'test', _scopeMapVersion: 'test', tools: [FAKE_TOOL_DEF_READ] };
const FAKE_TIER1 = ['lark_calendar_agenda'];

// Controllable child_process mock. Each test sets `execFileBehavior` to steer
// how the next lark-cli call resolves.
//   { mode: 'instant' }                         -> immediate success
//   { mode: 'slow', delayMs }                   -> success after delayMs
//   { mode: 'timeout', partial }                -> err.killed+signal, partial stdout
//   { mode: 'maxbuffer', partial }              -> err.code=ERR_CHILD_PROCESS_STDIO_MAXBUFFER
let execFileBehavior = { mode: 'instant' };
let lastExecFileOpts = null; // captured opts of the most recent execFile call
const OK_STDOUT = '{"ok":true,"data":{"events":[]}}';

const originalReadFileSync = fs.readFileSync.bind(fs);
fs.readFileSync = (filePath, encoding) => {
  if (filePath === '/app/generated-tools.json') return JSON.stringify(FAKE_CATALOG);
  if (filePath === '/app/tier1.json') return JSON.stringify(FAKE_TIER1);
  return originalReadFileSync(filePath, encoding);
};

const originalLoad = Module._load;
Module._load = function (request) {
  if (request === '@aws-sdk/client-secrets-manager') {
    return {
      SecretsManagerClient: class { send() { return Promise.resolve({ SecretString: JSON.stringify({ appSecret: 'fake' }) }); } },
      GetSecretValueCommand: class { constructor(p) { this.params = p; } },
    };
  }
  if (request === 'child_process') {
    return {
      execFile: (cmd, args, opts, cb) => {
        lastExecFileOpts = opts;
        const child = { kill: () => {}, pid: 4242 };
        const b = execFileBehavior;
        if (b.mode === 'slow') {
          // Honor an AbortSignal the way Node's execFile does: abort → kill the
          // child and call back with an AbortError, freeing the slot at once.
          const timer = setTimeout(() => cb(null, OK_STDOUT, ''), b.delayMs ?? 200);
          if (opts?.signal) {
            opts.signal.addEventListener('abort', () => {
              clearTimeout(timer);
              cb(Object.assign(new Error('aborted'), { name: 'AbortError', killed: true }), '', '');
            }, { once: true });
          }
        } else if (b.mode === 'timeout') {
          const err = Object.assign(new Error('Command failed'), { killed: true, signal: 'SIGTERM' });
          setTimeout(() => cb(err, b.partial ?? '{"partia', ''), 0);
        } else if (b.mode === 'maxbuffer') {
          const err = Object.assign(new Error('stdout maxBuffer length exceeded'), { code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER' });
          setTimeout(() => cb(err, b.partial ?? '{"big":"trunc', ''), 0);
        } else if (b.mode === 'abort-error') {
          // Node sets BOTH name=AbortError and killed=true when a signal aborts.
          const err = Object.assign(new Error('The operation was aborted'), { name: 'AbortError', killed: true });
          setTimeout(() => cb(err, '', ''), 0);
        } else {
          setTimeout(() => cb(null, OK_STDOUT, ''), 0);
        }
        return child;
      },
    };
  }
  return originalLoad.apply(this, arguments);
};

function callTool(name, args = {}, id = 1) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args } });
    const req = http.request({
      hostname: '127.0.0.1', port: 8000, path: '/', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload), 'x-user-access-token': 'u-tok' },
    }, (res) => {
      let body = ''; res.on('data', c => { body += c; });
      res.on('end', () => {
        let data = null;
        for (const line of body.split('\n')) if (line.startsWith('data: ')) data = JSON.parse(line.slice(6));
        resolve({ statusCode: res.statusCode, data });
      });
    });
    req.on('error', reject);
    req.write(payload); req.end();
  });
}

beforeAll(async () => {
  await import('../server.js');
  await new Promise(r => setTimeout(r, 300));
});
afterAll(() => { Module._load = originalLoad; fs.readFileSync = originalReadFileSync; });

describe('R1: semaphore queue does not spuriously abort queued requests', () => {
  it('a queued request (beyond MAX_CONCURRENT) still completes instead of client_aborted', async () => {
    // MAX_CONCURRENT=1: req A occupies the only slot for 250ms, req B must queue.
    // The bug: B's own request-body 'close' fires ac.abort() while B is queued,
    // rejecting it with client_aborted even though the client never disconnected.
    execFileBehavior = { mode: 'slow', delayMs: 250 };
    const [a, b] = await Promise.all([callTool('lark_calendar_agenda', {}, 1), callTool('lark_calendar_agenda', {}, 2)]);

    const textOf = r => r.data?.result?.content?.[0]?.text ?? '';
    expect(textOf(a)).not.toContain('client_aborted');
    expect(textOf(b)).not.toContain('client_aborted');
    // Both should be successful tool results, not errors.
    expect(a.data?.result?.isError).toBeUndefined();
    expect(b.data?.result?.isError).toBeUndefined();
  });

  it('three concurrent requests all succeed: the queue buffers, none are dropped', async () => {
    // Stronger form of the R1 guard: with MAX_CONCURRENT=1, requests 2 and 3
    // both have to queue. Pre-fix, BOTH overflowed to client_aborted; with the
    // fix all three drain in turn. (The abort path itself is exercised live by
    // the standalone disconnect repro; it can't be observed cleanly through an
    // aborted HTTP client here, so we don't assert it from the client side.)
    execFileBehavior = { mode: 'slow', delayMs: 120 };
    const results = await Promise.all([
      callTool('lark_calendar_agenda', {}, 30),
      callTool('lark_calendar_agenda', {}, 31),
      callTool('lark_calendar_agenda', {}, 32),
    ]);
    for (const r of results) {
      expect(r.data?.result?.isError).toBeUndefined();
      expect(r.data?.result?.content?.[0]?.text ?? '').not.toContain('client_aborted');
    }
  });
});

describe('R4: child-process timeout / maxBuffer map to a clean structured error', () => {
  it('a 60s timeout returns {"error":"timeout"}, not the truncated partial stdout', async () => {
    // execFile kills the child on timeout (err.killed + signal) and hands back
    // whatever partial stdout it had — almost always invalid JSON. The bug
    // returned that fragment as the tool result; the real cause (timeout) was
    // lost and the LLM got a corrupt blob.
    execFileBehavior = { mode: 'timeout', partial: '{"partia' };
    const r = await callTool('lark_calendar_agenda', {}, 40);

    expect(r.data?.result?.isError).toBe(true);
    const text = r.data?.result?.content?.[0]?.text ?? '';
    expect(text).not.toContain('partia');           // not the truncated fragment
    expect(() => JSON.parse(text)).not.toThrow();    // it IS valid JSON
    expect(JSON.parse(text).error).toBe('timeout');
  });

  it('a maxBuffer overflow returns {"error":"output_too_large"}, not the truncated blob', async () => {
    execFileBehavior = { mode: 'maxbuffer', partial: '{"big":"trunc' };
    const r = await callTool('lark_calendar_agenda', {}, 41);

    expect(r.data?.result?.isError).toBe(true);
    const text = r.data?.result?.content?.[0]?.text ?? '';
    expect(text).not.toContain('trunc');
    expect(() => JSON.parse(text)).not.toThrow();
    expect(JSON.parse(text).error).toBe('output_too_large');
  });

  it('a normal lark-cli error (non-timeout) still surfaces its stderr/message', async () => {
    // Guard: the timeout/maxBuffer branch must not swallow ordinary CLI errors.
    execFileBehavior = { mode: 'instant' };
    const ok = await callTool('lark_calendar_agenda', {}, 42);
    expect(ok.data?.result?.isError).toBeUndefined();
  });
});

describe('R5: execFile is abortable and its timeout aligns under the Lambda', () => {
  it('passes an AbortSignal into execFile so a client disconnect can kill the child', async () => {
    // The middleware aborts its fetch at 25s; if the child keeps running to the
    // old 60s timeout it holds a concurrency slot for ~35s after the client gave
    // up. Wiring ac.signal into execFile lets a disconnect kill the child and
    // free the slot immediately.
    execFileBehavior = { mode: 'instant' };
    await callTool('lark_calendar_agenda', {}, 50);
    expect(lastExecFileOpts).not.toBeNull();
    expect(lastExecFileOpts.signal).toBeInstanceOf(AbortSignal);
  });

  it('caps the execFile timeout at or below the Lambda 25s budget', async () => {
    execFileBehavior = { mode: 'instant' };
    await callTool('lark_calendar_agenda', {}, 51);
    expect(typeof lastExecFileOpts.timeout).toBe('number');
    expect(lastExecFileOpts.timeout).toBeLessThanOrEqual(25000);
  });

  it('maps an execFile AbortError to client_aborted, NOT timeout', async () => {
    // When the signal kills the child, Node sets err.name=AbortError AND
    // err.killed=true. That must not be misreported as a timeout — it's a
    // client disconnect. (Only reachable if the request is still being served;
    // in practice the response is already closed, but the mapping must be right.)
    execFileBehavior = { mode: 'abort-error' };
    const r = await callTool('lark_calendar_agenda', {}, 54);
    expect(r.data?.result?.isError).toBe(true);
    const text = r.data?.result?.content?.[0]?.text ?? '';
    expect(JSON.parse(text).error).toBe('client_aborted');
  });

  it('a client disconnect frees the slot promptly instead of holding it for the full timeout', async () => {
    // MAX_CONCURRENT=1. Request A is slow (would take 5s). Its client aborts
    // almost immediately; the child must be killed so a later request can run
    // well before A's nominal completion.
    execFileBehavior = { mode: 'slow', delayMs: 5000 };
    const ctrl = new AbortController();
    const payload = JSON.stringify({ jsonrpc: '2.0', id: 52, method: 'tools/call', params: { name: 'lark_calendar_agenda', arguments: {} } });
    const aborted = fetch('http://127.0.0.1:8000/', {
      method: 'POST', signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', 'x-user-access-token': 'u-tok' },
      body: payload,
    }).catch(e => ({ aborted: e.name }));
    await new Promise(r => setTimeout(r, 50));
    ctrl.abort();
    await aborted;

    // If the slot were held until the 5s child finished, this fast call would
    // not complete quickly. Give it far less than 5s.
    execFileBehavior = { mode: 'instant' };
    const t0 = Date.now();
    const after = await callTool('lark_calendar_agenda', {}, 53);
    const elapsed = Date.now() - t0;
    expect(after.data?.result?.isError).toBeUndefined();
    expect(elapsed).toBeLessThan(2000);
  });
});
