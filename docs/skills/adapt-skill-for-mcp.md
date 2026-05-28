---
name: adapt-skill-for-mcp
description: "Transform a raw lark-cli skill into MCP-adapted format. Use when upgrading lark-cli skills for the Remote MCP server."
---

# Adapt lark-cli Skill for Remote MCP

Transform a raw lark-cli skill (designed for Claude Code local terminal) into a format
suitable for downstream agents calling our Remote MCP tools.

## Quick reference

| Rule | One-liner |
|------|-----------|
| 1 | Strip YAML frontmatter |
| 2 | `lark-cli ... +cmd --flags` → `lark_<svc>_<cmd>(flag="val")` |
| 3 | Remove `--as`, auth, identity setup |
| 4 | Cross-file links → `lark_get_skill(domain, section)` |
| 5 | Parameter tables: `--kebab` → `snake_case`, remove `--as`/`--yes` rows |
| 6 | CLI terminology → tool terminology; delete pipelines |
| 6b | Bot-only ops → add ⚠️ warning |
| 7 | Preserve orchestration logic, CRITICAL markers, language |

## When to use

After upgrading lark-cli (`lark-cli update`), re-adapt skills into `docker/skills/`.

## Runtime architecture (context for adaptation)

The MCP server exposes tools to downstream agents. The call chain:

```
Agent → MCP tools/call {name: "lark_calendar_create", arguments: {summary: "x", start: "y"}}
  → server.js converts arguments to CLI flags: lark-cli calendar +create --summary "x" --start "y"
  → lark-cli executes with user token → returns JSON
  → server.js returns result to agent
```

Key implications for adapted skills:
- **Parameter names** in skill examples must be `snake_case` (matching inputSchema)
- **The agent never runs lark-cli directly** — it calls MCP tools
- **Auth is transparent** — user token is injected by the server per-request
- **Identity is always `user`** — `LARKSUITE_CLI_DEFAULT_AS=user` is hardcoded
- **High-risk writes** require `_confirm=true` (server rejects first call with guidance)
- **`params` and `data` for raw APIs** are JSON strings, not nested objects

## Input / Output

- **Input**: A raw skill directory (e.g. `~/.agents/skills/lark-calendar/`)
- **Output**: Adapted files written to `docker/skills/lark-calendar/`

## Transformation Rules

### 1. Strip YAML frontmatter

Remove the `---...---` block at the top (contains `bins`, `cliHelp` metadata irrelevant to MCP).

### 2. Replace CLI commands with MCP tool calls

The MCP server receives `{"name": "tool_name", "arguments": {...}}` and internally converts
arguments back to `--flag value` when calling lark-cli. Adapted skills should show the
**agent-facing format** (function-call shorthand that maps directly to MCP arguments):

| Original (CLI) | Adapted (MCP) |
|----------------|---------------|
| `lark-cli calendar +create --summary "x" --start "y" --end "z"` | `lark_calendar_create(summary="x", start="y", end="z")` |
| `lark-cli calendar events create --params '{...}' --data '{...}'` | `lark_invoke(tool_name="lark_calendar_events_create", args={params: {"calendar_id":"xxx"}, data: {"summary":"y"}})` |
| `lark-cli schema calendar.events.create` | `lark_discover(query="calendar.events.create")` |
| `lark-cli calendar -h` | `lark_discover(category="calendar")` |

**Rules:**

- **Tool naming**: Shortcut `+<cmd>` → `lark_<service>_<cmd>`; Raw API `<service> <resource> <method>` → via `lark_invoke(tool_name="lark_<service>_<resource>_<method>")`; dots in resource names become underscores
- **Parameter names**: Convert `--kebab-case` to `snake_case` (must match the tool's inputSchema exactly)
- **String params**: Most args are strings — `flag_name="value"`
- **Boolean params**: `page_all=true`, `overwrite=true`. Both bare `true` and `"true"` work at runtime (server checks truthiness), but prefer bare `true` for clarity.
- **`--params` and `--data`**: In the skill pseudo-code, write as readable JSON objects for clarity: `params={"calendar_id": "xxx"}, data={"summary": "y"}`. The MCP client serializes these as JSON strings on the wire. (Do NOT leave multi-line JSON blobs orphaned outside the function call.)
- **Multi-line commands**: Collapse backslash continuations AND multi-line `--data '{...}'` blobs into a single tool call
- **`| jq` pipelines**: Delete. The MCP caller handles JSON parsing.
- **`| tr`, `| grep`, shell variable assignment** (e.g. `TOKEN=$(lark-cli ...)`): Delete. Show only the tool call.
- **Hidden flags** (never appear in adapted output): `--as`, `--dry-run`, `--jq`, `--yes`, `--help`. These are handled by the server or irrelevant to MCP consumers. Note: `--format` IS exposed in some tools (e.g., `format="json"`) — include it only when the skill explicitly needs a non-default format.

### 3. Remove identity / auth instructions

The MCP server handles authentication transparently. Remove or neutralize:

- `--as user` / `--as bot` flags — remove entirely from tool calls
- Where the original text distinguishes "user identity" vs "bot identity" behavior, preserve the semantic distinction but replace backtick-quoted `--as user`/`--as bot` with readable labels like `user identity` and `bot identity` (not both as "user identity")
- `lark-cli auth login ...` lines — delete
- `lark-cli config init` lines — delete
- "Prerequisites: Read lark-shared/SKILL.md for auth..." — delete
- Sections explaining auth setup — delete or replace with: "(authentication is handled automatically by the MCP server)"
- Empty code blocks left after stripping auth commands — delete

### 4. Replace cross-file references and "Read 工具" instructions

| Original | Adapted |
|----------|---------|
| `先用 Read 工具读取 [references/lark-calendar-schedule-meeting.md](...)` | `先调用 lark_get_skill(domain="calendar", section="schedule-meeting")` |
| `MUST 先用 Read 工具读取以下文件` | Delete or replace with `先调用 lark_get_skill(domain="...", section="...")` |
| `[../lark-shared/SKILL.md](...)` | Delete (auth is automatic) |
| `lark_get_skill(domain="shared")` | Delete — shared is excluded, this is a dead reference. Replace with "(MCP server 自动处理认证)" |
| `[../lark-vc/SKILL.md](...)` | `lark_get_skill(domain="vc")` |
| `[vc +recording](../lark-vc/references/lark-vc-recording.md)` | `lark_get_skill(domain="vc", section="recording")` |
| `[text](references/local-file.md)` (intra-skill) | `lark_get_skill(domain="<current>", section="<filename-without-prefix>")` |
| `[text](../SKILL.md)` (parent ref within same skill) | `lark_get_skill(domain="<current>")` |

**Section name resolution**: The server tries these paths in order:

```
section="X" →
  1. references/X.md
  2. references/lark-<domain>-X.md
  3. <skillDir>/X.md

section="subdir/filename" →
  1. references/subdir/filename.md    ← subdirs work via /
  2. references/lark-<domain>-subdir/filename.md
  3. <skillDir>/subdir/filename.md    ← routes/, scenes/ etc.
```

**Rules for section values:**

| File path | Correct section |
|-----------|----------------|
| `references/lark-task-create.md` | `"create"` (strip `lark-<domain>-` prefix) |
| `references/examples.md` | `"examples"` |
| `references/style/lark-doc-style.md` | `"style/lark-doc-style"` (include subdir) |
| `routes/dsl.md` | `"routes/dsl"` |
| `scenes/flowchart.md` | `"scenes/flowchart"` |

**CRITICAL**: Shortcut tables in SKILL.md often have rows like `[+create](references/lark-task-create.md)`.
These MUST be converted. Do NOT leave any `](references/` patterns in the output — they are
filesystem paths that downstream agents cannot resolve.

### 5. Convert parameter tables

Original skills often have tables with `--flag` column. Convert to snake_case:

| Before | After |
|--------|-------|
| `--summary <text>` | `summary` |
| `--start <ISO8601>` | `start` |
| `--attendee-ids <ids>` | `attendee_ids` |
| `--page-all` (boolean) | `page_all` (boolean) |
| `--as <identity>` | _(delete row)_ |
| `--yes` | _(delete row — server handles)_ |

Keep the description and required/optional columns intact.

### 6. Clean up CLI terminology and pipelines

- `CLI/API 返回的` → `工具返回的`
- `CLI 标志` → `参数`
- `调用任何具体的 CLI 子命令` → `调用任何具体的 MCP tool`
- `| jq '...'` or `| tr ...` post-processing pipelines → delete (caller handles JSON parsing)
- Keep "CLI" in purely descriptive/historical context (acceptable)

### 6b. Handle bot-only operations

The MCP server always uses **user identity** (user_access_token). If a tool/operation is
documented as bot-only (`tenant_access_token` required, no user auth support), add a note:

> ⚠️ This operation requires bot identity and is not available via the MCP server.

### 7. Preserve everything else

- All orchestration logic (workflow steps, decision rules, constraints)
- All CRITICAL / BLOCKING REQUIREMENT markers
- All parameter tables (but remove `--as` rows)
- All conceptual explanations
- Original language (Chinese stays Chinese, English stays English)
- Markdown formatting

## Excluded skills (do not adapt)

- `lark-shared` — auth-only, not relevant
- `lark-skill-maker` — dev tool for creating skills
- `lark-event` — real-time event consumption (not exposed via Remote MCP)

## Conditional guards

Apply transformation **only if** the pattern is in an actionable context (code block, inline
backtick, or direct instruction). **Skip if** the pattern is in:

- A comment explaining historical context ("originally this was done via lark-cli...")
- A default value literal (e.g., `--source-title` default is `"created by lark-cli"`)
- An error message description ("if lark-cli returns error.code=20017...")
- A comparison or "do not" instruction ("do NOT call lark-cli directly")

When in doubt, convert — a false positive (converting descriptive text) is less harmful than
a false negative (leaving an actionable CLI command unconverted).

## Execution workflow

### Phase 1: Transform

Dispatch as many agents in parallel as possible — there are no dependencies between skills.

| Complexity | Skills | Strategy |
|-----------|--------|----------|
| High (10+ references) | calendar, base, drive, im, doc | Solo agent per skill (5 agents) |
| Medium (3-9 references) | mail, task, wiki, sheets, whiteboard, vc | Solo agent per skill (6 agents) |
| Low (1-2 files) | approval, attendance, contact, okr / markdown, slides, apps, minutes / workflow-meeting-summary, workflow-standup-report, openapi-explorer, vc-agent | 3 agents (3-4 skills each) |

**Target: 14 parallel agents.** No skill depends on another — full parallelism is safe.

Each agent, per skill:

1. Read raw SKILL.md from `~/.agents/skills/lark-<domain>/SKILL.md`
2. Apply transformation rules (respect conditional guards)
3. Write result to `docker/skills/lark-<domain>/SKILL.md`
4. For each `.md` file in the skill directory (references/, routes/, scenes/, style/, etc.):
   - Read, apply same rules, write to same relative path under `docker/skills/lark-<domain>/`
   - Note: files in subdirs like `references/style/` are accessible to agents via full SKILL.md text but not individually via `lark_get_skill(section=...)`. Preserve their directory structure as-is.
5. Self-verify: `grep -c "lark-cli"` on all output files — must be 0

### Phase 2: Verify

After all agents complete:

```bash
find docker/skills -name "*.md" -exec grep -l "lark-cli" {} \;         # must be empty
find docker/skills -name "*.md" -exec grep -ln "\.\./lark-" {} \;      # no dead cross-links
find docker/skills -name "*.md" -exec grep -ln "\-\-as " {} \;         # no --as leaks
find docker/skills -name "*.md" -exec grep -ln "Read 工具\|Read tool" {} \;  # no Read tool refs
```

### Phase 3: Review

Dispatch review agents to cover **all** adapted skills (not just spot-check). Group similarly
to Phase 1 for maximum parallelism (~14 agents). Each review agent:

1. Read every `.md` file in its assigned `docker/skills/lark-<domain>/` directories
2. Check against the Quality checklist below — report issues with file path and line number
3. Explicitly list all files reviewed and mark each as PASS or ISSUE

**Acceptance criteria**: All skills must PASS all checklist items. If issues are found,
fix them (either re-dispatch a transform agent for that skill, or fix inline), then
re-review the affected files only.

## Quality checklist (per skill)

- [ ] Zero `lark-cli` in code blocks and inline backticks
- [ ] All `--flag value` converted to `flag="value"` inside tool call parens
- [ ] `--params`/`--data` as readable JSON objects: `args={params: {"key":"val"}, data: {...}}` (not orphaned multi-line blobs)
- [ ] No dead `../lark-*` cross-skill links
- [ ] No `](references/` intra-skill filesystem links (must be converted to `lark_get_skill`)
- [ ] No `lark_get_skill(domain="shared")` (dead reference)
- [ ] No `Read 工具` / `Read tool` instructions (use `lark_get_skill` instead)
- [ ] No empty backticks or `(identity)` where bot/user distinction was lost
- [ ] No `--as user/bot` in code examples
- [ ] No `| jq` or shell pipeline post-processing
- [ ] Parameter tables use `snake_case` names (no `--kebab-case`)
- [ ] All `lark_get_skill(section="X")` references resolve to actual files in `references/`
- [ ] Orchestration logic reads coherently
- [ ] Bot-only operations flagged with warning
- [ ] Every resource file (references/, routes/, scenes/) is mentioned by at least one .md in the same skill
- [ ] Subdir sections use full path: `section="style/lark-doc-style"` not `section="style"`

## Correct and incorrect examples

### Tier1 shortcut tool (e.g. `lark_calendar_create`)

The MCP inputSchema for this tool has parameters: `summary` (string), `start` (string),
`end` (string), `attendee_ids` (string), `calendar_id` (string), `description` (string),
`rrule` (string). Hidden: `--as`, `--dry-run`, `--format`, `--jq`, `--yes`.

**Correct:**
```
lark_calendar_create(summary="产品评审", start="2026-03-12T14:00+08:00", end="2026-03-12T15:00+08:00", attendee_ids="ou_aaa,ou_bbb")
```

**Incorrect** (flag style after call):
```
lark_calendar_create(summary="产品评审", start="2026-03-12T14:00+08:00") \
  --end "2026-03-12T15:00+08:00" \
  --attendee-ids ou_aaa,ou_bbb
```

**Incorrect** (kebab-case params):
```
lark_calendar_create(summary="产品评审", start="2026-03-12T14:00+08:00", attendee-ids="ou_aaa")
```

**Incorrect** (includes --as):
```
lark_calendar_create(as="user", summary="产品评审", start="2026-03-12T14:00+08:00")
```

### Raw API via `lark_invoke`

The `lark_invoke` tool accepts `tool_name` (string) and `args` (object). The `args` keys
map to CLI flags: `params`, `data`, `page_all`, `page_limit`, `format`.
Write `params` and `data` as readable JSON objects in the pseudo-code — the MCP client
handles serialization.

**Correct:**
```
lark_invoke(tool_name="lark_calendar_events_create", args={
  params: {"calendar_id": "<CALENDAR_ID>"},
  data: {"summary": "技术分享", "start_time": {"timestamp": "1741586400"}, "end_time": {"timestamp": "1741593600"}}
})
```

**Incorrect** (orphaned JSON lines outside the function call):
```
lark_invoke(tool_name="lark_calendar_events_create", args={params: {"calendar_id":"xxx"}})
  "summary": "技术分享",
  "start_time": { "timestamp": "1741586400" }
}'
```

**Incorrect** (multi-line `--data` not collapsed):
```
lark_invoke(tool_name="lark_calendar_events_create", args={params: {"calendar_id":"xxx"}}) \
  --data '{
  "summary": "技术分享"
}'
```

**Incorrect** (shell variable assignment):
```
EVENT_ID=$(lark_invoke(tool_name="lark_calendar_events_create", args={...}))
```
Correct: just show the tool call — the caller gets the JSON response directly.

### Boolean parameters

Tools like `lark_wiki_node_list` have boolean flags: `page_all`.

**Correct:** `lark_wiki_node_list(space_id="xxx", page_all=true)`

**Acceptable:** `lark_wiki_node_list(space_id="xxx", page_all="true")` (works but prefer bare true)

**Incorrect:** `lark_wiki_node_list(space_id="xxx", page_all="--page-limit")` (flag name as value — broken conversion artifact)

### `lark_discover` and `lark_get_skill`

**Correct:** `lark_discover(query="calendar.events.create")` — find a tool and its schema

**Correct:** `lark_discover(category="calendar")` — list all tools in a domain

**Correct:** `lark_get_skill(domain="calendar", section="schedule-meeting")` — get orchestration guide

**Incorrect:** `lark-cli schema calendar.events.create` (CLI command, not MCP tool)

**Incorrect:** `先用 Read 工具读取 references/xxx.md` (local file access, not available in MCP)
