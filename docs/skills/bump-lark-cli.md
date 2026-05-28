---
name: bump-lark-cli
description: "Upgrade lark-cli version pin: bump Dockerfile, re-extract shortcut-scopes.json from source, regenerate scope-allowlist.ts, update snapshot. Use when a new lark-cli version is released."
---

# Upgrade lark-cli Version

## When to use

When a new lark-cli version is released and needs to be pinned in this project.

## Prerequisites

- The target version tag (e.g. `v1.0.40`) must exist at https://github.com/larksuite/cli
- `lark-cli --version` locally should match or exceed the target (for validation)

## Steps

### 1. Create branch

```bash
git checkout -b chore/bump-lark-cli-<VERSION>
```

### 2. Update Dockerfile pin

Edit `docker/Dockerfile` line `ARG LARK_CLI_VERSION=...` to the new version.

### 3. Clone source and extract shortcut-scopes.json

```bash
cd /tmp && git clone --depth=1 --branch v<VERSION> https://github.com/larksuite/cli.git lark-cli-<VERSION>
python3 scripts/extract-shortcut-scopes.py /tmp/lark-cli-<VERSION> <VERSION>
```

The script (`scripts/extract-shortcut-scopes.py`) handles:
- UserScopes-first strategy (prefer UserScopes → fallback Scopes → include ConditionalScopes → exclude BotScopes)
- Variable/constant resolution (single strings, slices, and `append()` combos)
- Multiple `common.Shortcut{}` definitions per file
- Service name constants
- Empty scope arrays (included as `[]`)

### 4. Regenerate scope-allowlist.ts

```bash
scripts/build-scope-allowlist.sh
```

This regenerates `lambda/token-refresh-shim/scope-allowlist.ts` from `docker/shortcut-scopes.json` + `config/oauth-scopes.json`.

### 5. Verify consistency

```bash
scripts/check-lark-cli-version.sh   # Dockerfile ↔ shortcut-scopes.json version match
```

### 5b. Update default OAuth scopes

Compare tier1 tool scopes against `config/oauth-scopes.json`:

```bash
python3 -c "
import json
with open('docker/tier1.json') as f: tier1 = set(json.load(f))
with open('docker/shortcut-scopes.json') as f: data = json.load(f)
with open('config/oauth-scopes.json') as f: defaults = set(json.load(f))
needed = set()
for s in data['shortcuts']:
    tool = f\"lark_{s['service']}_{s['command'].lstrip('+').replace('-','_')}\"
    if tool in tier1:
        needed.update(s['scopes'])
missing = sorted(needed - defaults)
if missing:
    print('Add to config/oauth-scopes.json:')
    for s in missing: print(f'  {s}')
else:
    print('OK: all tier1 scopes covered')
"
```

If scopes are missing, add them to `config/oauth-scopes.json` (grouped near related entries),
then re-run `scripts/build-scope-allowlist.sh`.

### 6. Update CDK snapshot

```bash
npx vitest run infra/test/snapshot.test.ts --update
```

### 7. Run full tests

```bash
npm test   # All 13 test files / 246+ tests must pass (includes scope-coverage)
```

The `scope-coverage` test validates:
- All tier1 tool scopes are in `config/oauth-scopes.json`
- Every tier1 tool has a shortcut-scopes entry
- Extraction covers all lark-cli runtime shortcuts (no gaps)

### 8. Commit

Include all changed files:
- `docker/Dockerfile`
- `docker/shortcut-scopes.json`
- `config/oauth-scopes.json` (if updated)
- `lambda/token-refresh-shim/scope-allowlist.ts`
- `infra/test/__snapshots__/snapshot.test.ts.snap`

## Validation checklist

- [ ] No bot-only scopes in shortcut-scopes.json (e.g. `im:message:send_as_bot` should NOT appear)
- [ ] `scripts/check-lark-cli-version.sh` passes
- [ ] `npm test` passes (scope-coverage test catches missing oauth-scopes)
- [ ] `git diff --stat` shows only the expected files (4-5 depending on oauth-scopes changes)
- [ ] No remaining references to old version (`grep -r "OLD_VERSION" --include="*.json" --include="Dockerfile*"`)

## Scope extraction strategy reference

```
Source field priority (per shortcut):
  UserScopes  →  user OAuth scopes (preferred)
  Scopes      →  generic/fallback (when no UserScopes)
  ConditionalScopes → runtime-triggered (always included)
  BotScopes   →  EXCLUDED (bot-only, not relevant)
```

Why: This project uses user OAuth (3-legged). The scope-allowlist limits incremental-auth
`extra_scope=` parameter to prevent phishing. Bot scopes can never be granted via user
consent, so including them would be noise in the allowlist and confusing for incremental auth.
