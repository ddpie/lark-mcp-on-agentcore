# Playbooks — Recipes for Common Changes

Each recipe lists the files to touch (in order) and the check to run. For the
coupling rationale, see `docs/agent/invariants.md`.

## Add a Tier-1 (high-frequency) tool

1. Edit `docker/tier1.json` — add the tool entry (name `lark_<service>_<command>`).
2. Ensure its scope is present in `docker/shortcut-scopes.json`; if missing, the
   tool's command isn't in the pinned lark-cli — stop and reconsider.
3. If the tool needs a scope not yet in first-time auth, add it to
   `config/oauth-scopes.json`.
4. Run `./scripts/audit-tools.sh` (15 structural assertions) and `./scripts/test.sh`.
5. Update the tool-count/Tier-1 wording in `README.md` if the count changed.

## Add an OAuth scope

1. Confirm the scope is user-identity (not bot-only).
2. Add to `config/oauth-scopes.json` if it should be requested at first auth.
3. Regenerate the allowlist: `./scripts/build-scope-allowlist.sh` (do NOT hand-edit
   `lambda/token-refresh-shim/scope-allowlist.ts`).
4. Run `./scripts/test.sh`.

## Add a CloudWatch alarm

1. Edit `infra/lib/oauth-stack.ts` (alarm definition) and, if it needs a tunable
   threshold, `config/alarm-thresholds.json` (+ presets in `config/alarm-presets.json`).
2. Add any user-facing strings to `config/i18n.json` (zh + en).
3. Update CDK snapshot: `cd infra && npm run test:update`.
4. Document it in `docs/observability_en.md` AND `docs/observability_zh.md`.

## Bump lark-cli

Follow the full runbook: `docs/skills/bump-lark-cli.md`. Do not shortcut it —
it coordinates 6 file groups (Dockerfile, scopes, allowlist, skills,
oauth-scopes, CDK snapshot). Verify with `./scripts/check-lark-cli-version.sh`
and `./scripts/test.sh --full`.
