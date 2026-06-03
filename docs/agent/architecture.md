# Architecture — Mental Model for AI Agents

Read this before changing how requests flow, where tokens live, or how the tool
catalog / OAuth scopes are produced. Human-facing docs (README, structure,
security) describe *what* the system is; this describes *what happens to a
request as it crosses the system*, which is what you need before editing it.

Code pointers below use function/handler names as stable anchors — grep the name
rather than trusting line numbers.

## Request lifecycle (one tool call)

Client (remote-MCP, e.g. Quick Desktop)
  → CloudFront (HTTPS edge, optional WAFv2 rate limiting)
  → API Gateway
  → Middleware Lambda  (`lambda/mcp-middleware/index.ts`)
      · verifies the MCP token (custom HMAC-SHA256 scheme, NOT JWT)
      · re-signs the upstream call with SigV4
      · injects `X-User-Access-Token` (+ `X-Incr-Auth-Token`) headers
      · forwards `Mcp-Session-Id` (it forwards, never mints — MCP spec: server assigns)
      · hard 25s timeout (AgentCore/API-GW budget is ~29s)
  → AgentCore Runtime container (`docker/server.js`)
      · extracts the Feishu token from the header into the child-process env
      · runs `lark-cli` as a fresh child process per tool call (24s timeout, env `LARK_CLI_TIMEOUT_MS` default 24000; 10MB stdout cap)
      · returns the result

## Session isolation & concurrency (NOT in any human doc)

AgentCore gives **each MCP session its own dedicated microVM** (isolated
compute/memory/filesystem; up to 8h lifetime; idle-timeout configurable). The
`Mcp-Session-Id` header provides microVM stickiness. Therefore the
`MAX_CONCURRENT=10` / `MAX_QUEUE_DEPTH=20` semaphore (`docker/server-lib.js`,
function `createSemaphore`, wired up in `docker/server.js`) is
**per-session**, not a shared global pool — each session's microVM runs its own
`server.js` process with its own counter. User isolation is triple-layered:
microVM boundary → per-call child process → token passed via env, never shared.
(Human-facing writeup with a diagram — Feishu Token vs MCP Token vs the shared
identity-less MCP endpoint — is in `docs/security_en.md` → "User Isolation".)

Container lifecycle (relevant when touching startup/shutdown or concurrency):
`/ping` returns 503 until the app secret has loaded (`docker/server.js`, the
`GET /ping` health-check handler); on shutdown the server drains in-flight calls
~5s, then `SIGTERM` then `SIGKILL`s any remaining lark-cli children
(`docker/server.js`, function `shutdown`).

## Provisioning split (CDK vs deploy.sh) — read before changing Runtime config

Infra is **not** all owned by CDK. The split:

- **CDK** owns: the Docker image (`DockerImageAsset`) + the AgentCore IAM
  `RuntimeRole` (`infra/lib/runtime-stack.ts` — that file does *only* these two
  and emits CfnOutputs consumed by deploy.sh), plus the OAuth/middleware Lambdas,
  alarms/dashboard, and optional WAF.
- **`scripts/deploy.sh`** (boto3 `bedrock-agentcore-control`) owns the **AgentCore
  Runtime itself and its endpoint** — `create_agent_runtime` / `update_agent_runtime`
  at `scripts/deploy.sh:~1049-1096`, endpoint at `~1119-1127`. That call defines the
  Runtime's `environmentVariables` (`APP_ID`, `AUTHORIZE_BASE`, `APP_SECRET_ID` that
  `docker/server.js` reads — the `APP_ID` / `APP_SECRET_ID` / `AUTHORIZE_BASE`
  env reads near the top of the file), `lifecycleConfiguration.idleRuntimeSessionTimeout`,
  and `requestHeaderConfiguration.requestHeaderAllowlist`
  (`['X-User-Access-Token','X-Runtime-User-Id','X-Incr-Auth-Token']`).

**Implication:** to change the Runtime's env vars, idle timeout, or allowed request
headers, edit `scripts/deploy.sh` and re-run it — editing `runtime-stack.ts` +
`cdk deploy` will NOT change them. The middleware's `X-User-Access-Token` /
`X-Incr-Auth-Token` headers only reach the container because of the deploy.sh
allowlist.

## Tool dispatch & skills (the heart of server.js)

`docker/server.js` speaks three MCP methods: `initialize`, `tools/list`,
`tools/call`. Of the catalog, **28 tier-1 (high-frequency) tools are exposed
directly**; the long tail is reached via `lark_discover` → `lark_invoke`. Two
meta-tools, `lark_list_skills` and `lark_get_skill`, serve the domain guides under
`docker/skills/**` and clients are instructed (via tool descriptions) to call them
FIRST. So "tier-1" means direct-exposed vs the discover/invoke fallback, and
editing tool exposure or skill-serving lives in `docker/server.js`.

## Risk classification & destructive-write gating

Each tool is tagged by `detectRisk` (`docker/generate-tools-lib.js`, function
`detectRisk`) as `read` / `write` / `high-risk-write` — by a `risk:` marker in the
lark-cli help, else heuristics on delete/remove (and create/send/update). At runtime
(`docker/server.js`, the `def.risk === 'high-risk-write' && args._confirm !== true`
guard) a `high-risk-write` tool is REFUSED unless `args._confirm===true` (returns
sentinel `user_approval_required`); `tools/list` surfaces `destructiveHint`
annotations so spec-compliant clients pop a confirm UI; and lark-cli's `--yes` is
injected only for commands that declare `supportsYes` (`docker/server.js`, the
`def.risk === 'high-risk-write' && def.supportsYes` line).

## Error envelope & permission-repair contract

Tool results are always `{content:[{type:'text',...}]}`; errors additionally set
`isError:true`. Sentinel error shapes that clients/middleware depend on:
`server_busy`, `user_approval_required`, `server_initializing`, `client_aborted`.
`patchPermissionError` (implemented in `docker/server-lib.js` — the single,
unit-tested source of truth, where `PERMISSION_ERROR_CODE = 99991679` lives;
`docker/server.js` imports and wraps it) detects Feishu error code `99991679`,
resolves the missing scopes, and rewrites the
error into an `authorize_url` (incremental auth) built from `AUTHORIZE_BASE` + the
`X-Incr-Auth-Token`. Do NOT change these error shapes or the 99991679 repair without
checking the middleware and clients that parse them.

## Token & identity (where each secret lives)

- User tokens: AWS Secrets Manager at `lark-mcp-on-agentcore/users/{userId}` (encrypted).
- App secret: Secrets Manager at `lark-mcp-on-agentcore/feishu-app`.
- Signing key: SSM Parameter Store; domain-separated HMAC keys derived from it
  (`oauth-state-v1`, `mcp-token-v1`, `mcp-incr-auth-v1`).
- OAuth codes + OpenID→userId mapping: DynamoDB (codes are single-use via
  conditional/atomic delete).
- Token auto-refresh: EventBridge every 30 min → `lambda/token-refresh-shim`.

## Build pipeline (what is generated, when)

- Tool catalog: `docker/generate-tools.js` runs at container build, emitting
  `generated-tools.json` (never committed). Driven by `docker/shortcut-scopes.json`.
- OAuth scope allowlist: `lambda/token-refresh-shim/scope-allowlist.ts` is
  regenerated by `scripts/build-scope-allowlist.sh` from both
  `docker/shortcut-scopes.json` and `config/oauth-scopes.json`.
- MCP skills: `docker/skills/**` are transformed from upstream lark-cli skills
  per `docs/skills/adapt-skill-for-mcp.md`.

See `docs/agent/invariants.md` for which of these must be regenerated together,
and `docs/agent/playbooks.md` for how to make common changes.
