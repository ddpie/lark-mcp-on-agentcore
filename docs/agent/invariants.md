# Invariants — Source-of-Truth Map & Couplings

If you change one side of a coupling below, you MUST update the other(s) in the
same change. Where an automated check exists, it is named; `scripts/check-invariants.sh`
(pre-commit) enforces the checkable subset.

## Source-of-truth vs generated (NEVER hand-edit the right column)

| Source of truth | Generated / derived (do not edit) | Regenerate with |
|---|---|---|
| `docker/Dockerfile` (`ARG LARK_CLI_VERSION`) | `docker/shortcut-scopes.json._meta.lark_cli_version` | `scripts/extract-shortcut-scopes.py` (via bump runbook) |
| `docker/shortcut-scopes.json` | `lambda/token-refresh-shim/scope-allowlist.ts` | `scripts/build-scope-allowlist.sh` |
| `docker/shortcut-scopes.json` | container `generated-tools.json` | container build (`docker/generate-tools.js`) |
| upstream lark-cli skills | `docker/skills/**` | re-adapt per `docs/skills/adapt-skill-for-mcp.md` |
| CDK source (`infra/lib/*.ts`) | `infra/cdk.out/**`, CDK snapshot | `cd infra && npm run test:update` |

Also never hand-edit: `node_modules/`, `coverage/`, `.stryker-tmp/`.

## Code ↔ code couplings

- **Bump lark-cli** ⇒ update Dockerfile pin, re-extract scopes, regenerate
  `scope-allowlist.ts`, re-adapt changed `docker/skills/**`, update CDK snapshot,
  reconcile `config/oauth-scopes.json`. Full procedure: `docs/skills/bump-lark-cli.md`.
  Check: `scripts/check-lark-cli-version.sh`.
- **Add/curate an OAuth scope** ⇒ it must exist in the generated allowlist
  (`scope-allowlist.ts`); regenerate, don't hand-add. Check: `scripts/audit-tools.sh`.
- **Change CDK stacks** ⇒ update the snapshot (`cd infra && npm run test:update`).
- **Change the Runtime's env vars / idle timeout / request-header allowlist** ⇒
  edit `scripts/deploy.sh` (boto3 `create/update_agent_runtime`), NOT CDK;
  `infra/lib/runtime-stack.ts` only builds the image + IAM role. See
  `docs/agent/architecture.md` (Provisioning split).

## Code ↔ doc couplings

- **Add/rename/remove a top-level directory** ⇒ update `docs/structure_en.md`
  AND `docs/structure_zh.md`. Check: `scripts/check-invariants.sh` (dir-exists).
- **Add/remove a `scripts/*.sh` command or a `test.sh` tier** ⇒ update the
  Commands section of `AGENTS.md`.
- **Add any `docs/*_en.md`** ⇒ add the `_zh.md` counterpart (and vice-versa).
  Check: `scripts/check-invariants.sh` (bilingual pairing).
- **`docs/agent/*` referenced by `AGENTS.md` must exist.** Check: `scripts/check-invariants.sh`.

## Identity boundary

- Only **user-identity** scopes are allowed; bot-only scopes must never leak into
  the allowlist or skills (see positioning: user-only, no bot). Verify during
  lark-cli bump skill review.

## Security invariants — do not relax without security review

These live in `lambda/token-refresh-shim/index.ts` (confused-deputy & token
safety). Do not loosen any of them without an explicit security review:

- **`userId` is accepted ONLY from the HMAC-signed `t=` token** (incremental-auth),
  never from a raw `user_id` query param — confused-deputy guard (`index.ts:~374-403`).
- **`extra_scope` is enforced against the generated allowlist** (`SCOPE_ALLOWLIST`
  from `scope-allowlist.ts`, checked at `index.ts:~404-416`) so a phishing link
  can't broaden the consent screen.
- **Auth codes are single-use** via an atomic DynamoDB `DeleteItem` with
  `ReturnValues=ALL_OLD` (`dynamodb-codes.ts:~29-45`); racing requests see one
  winner.
- **`preflightWritable` runs before consuming the single-use `refresh_token`**
  (`index.ts:~209,291`); if Secrets Manager storage fails *after* the token was
  burned, a CRITICAL `store_token_lost` log fires (`index.ts:~311-329`).
- **Scheduled refresh only fires past token half-life** (`remaining > totalTtl/2`
  ⇒ skip, `index.ts:~287-289`).
