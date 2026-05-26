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
```

Run the extraction script below against the cloned source. The extraction uses a **UserScopes-first strategy**:

- **Prefer `UserScopes`** (user OAuth scopes) when present
- **Fallback to `Scopes`** (generic) when no UserScopes defined
- **Include `ConditionalScopes`** (runtime-triggered scopes)
- **Exclude `BotScopes`** (not relevant for user OAuth flow)

The extraction must:
1. Strip Go comments before parsing (avoid false positives from comment text)
2. Resolve variable/constant references (e.g. `wbUpdateScopes`, `flagWriteLookupScopes`)
3. Handle multiple `common.Shortcut{}` definitions per file
4. Handle service name constants (e.g. `appsService` → `"apps"`)

Apply **minimal diff** to the existing `docker/shortcut-scopes.json`:
- Update `_meta.lark_cli_version` and `_meta.extracted_at`
- Only modify entries whose scope **set** actually changed (preserve existing array order)
- Append new scopes at end of existing arrays
- Add new shortcuts, remove deleted ones

### 4. Regenerate scope-allowlist.ts

```bash
scripts/build-scope-allowlist.sh
```

This regenerates `lambda/token-refresh-shim/scope-allowlist.ts` from `docker/shortcut-scopes.json` + `config/oauth-scopes.json`.

### 5. Verify consistency

```bash
scripts/check-lark-cli-version.sh   # Dockerfile ↔ shortcut-scopes.json version match
```

### 6. Update CDK snapshot

```bash
npx vitest run infra/test/snapshot.test.ts --update
```

### 7. Run full tests

```bash
npm test   # All 12 test files / 243+ tests must pass
```

### 8. Commit

Include all changed files:
- `docker/Dockerfile`
- `docker/shortcut-scopes.json`
- `lambda/token-refresh-shim/scope-allowlist.ts`
- `infra/test/__snapshots__/snapshot.test.ts.snap`

## Validation checklist

- [ ] No bot-only scopes in shortcut-scopes.json (e.g. `im:message:send_as_bot` should NOT appear)
- [ ] `scripts/check-lark-cli-version.sh` passes
- [ ] `npm test` passes
- [ ] `git diff --stat` shows only the 4 expected files
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
