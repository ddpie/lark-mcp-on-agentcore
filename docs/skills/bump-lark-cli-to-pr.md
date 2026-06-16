# Workflow: bump-lark-cli-to-pr

Automates the **safe prefix** of a lark-cli version bump: detect → branch →
deterministic regeneration → multi-agent skill re-adaptation + review panel →
offline gates → **draft PR, then STOP**. It deliberately does NOT deploy, does
NOT canary, and does NOT merge — those stay manual per `AGENTS.md` "Ask first".

This file documents the orchestration; it sits beside the runbook it automates
(`docs/skills/bump-lark-cli.md`). The runnable script is authored inline and
invoked via the `Workflow` tool (see "Running" below). Treat this `.md` as the
source of truth for the phases and the hard guardrails.

## Trigger

`scripts/check-lark-cli-upstream.sh` (run on a 6h cron). Only proceed when it
prints `{"newer":true,...}`. The `latest` field is the bump target.

**On the Ask-first boundary.** `AGENTS.md` lists "Bumping lark-cli" as Ask-first.
This workflow's stance: producing an unmerged **draft** PR is preparation, not the
bump itself — the human decision point (review + merge + deploy) is fully
preserved, and nothing reaches any environment without a person. The cron only
*drafts*; it never merges, deploys, or rolls out. If you want a person in the loop
even earlier, change the cron to notify-on-`newer:true` and run this workflow only
after manual approval.

## Hard guardrails (do not remove)

- **Stop at PR.** The final action is `gh pr create --draft`. Never `deploy.sh`,
  never `upgrade.sh`, never `gh pr merge`.
- **Bounded repair — one global counter.** A **single** repair counter, capped at
  **2**, is shared across phases 5 and 6 (it is NOT 2 per phase). Every ⚠️-driven
  transform re-dispatch (phase 5) and every offline-gate fix (phase 6) decrements
  the same budget. When it hits 0 and anything is still red, abort and hand the
  diff + failing output to the human. No unbounded "fix until clean" loop.
- **Offline only.** The gate is **`./scripts/test.sh`** (the official single entry
  point — includes unit + typecheck + lint + cdk-nag + scope-coverage) **then**
  `bash scripts/test-smoke-docker.sh` (builds the image + boots the container —
  catches broken artifacts `./scripts/test.sh` cannot). Use these exact two
  commands everywhere; do NOT substitute bare `npm test` or `npx vitest`, which
  cover a narrower set. No live Feishu API calls (no durable user OAuth token in
  unattended context).
- **Ask-first boundaries still apply — scope changes are NOT auto-applied.** This
  project is user-OAuth only; adding/removing scopes is Ask-first. If the Step 6b
  gap-check finds missing scopes, the workflow does **not** edit
  `config/oauth-scopes.json`. Consequently the `scope-coverage` test inside
  `./scripts/test.sh` will **fail by design** — this is an EXPECTED failure, must
  NOT consume the repair budget, and must NOT be "fixed" by the automation. Draft
  the PR anyway with the missing scopes called out under a prominent
  "⚠️ 需人工确认" heading, and STOP. Only a human adds the scopes + re-runs
  `scripts/build-scope-allowlist.sh`.

## Phases (mirror docs/skills/bump-lark-cli.md)

1. **Detect & branch** — read OLD from `docker/shortcut-scopes.json` `_meta`,
   NEW from the trigger. `git checkout -b chore/bump-lark-cli-<NEW>`. Bump
   `docker/Dockerfile` pin.
2. **Clone both trees** — guarded shallow clone of `v$OLD` and `v$NEW` into
   `/tmp/lark-cli-*` (Step 3 of the runbook, verbatim — the `[ -d ]` guard is
   required).
3. **Deterministic regen** (no agents, pure script):
   - `python3 scripts/extract-shortcut-scopes.py /tmp/lark-cli-$NEW $NEW`
   - `docker build -f docker/Dockerfile -t lark-mcp-bump:tmp docker/`
   - `scripts/extract-rawapi-scopes.sh lark-mcp-bump:tmp`
   - `scripts/build-scope-allowlist.sh`
   - `scripts/check-lark-cli-version.sh` (must pass)
   - Step 6b scope-gap check → **record** any missing scopes for the PR body. Do
     NOT edit `config/oauth-scopes.json` (Ask-first; see the scope guardrail).
   - `npx vitest run infra/test/snapshot.test.ts --update`
4. **Compute READAPT set** — Step 8 of the runbook (CHANGED ∪ ADDED \ REMOVED),
   delete stale dirs for REMOVED. If empty, skip phase 5. **Scope limit:** this
   automation only does the *diff-guided incremental* re-adapt. The runbook's
   "Force a FULL re-adapt" triggers (the `adapt-skill-for-mcp.md` transformation
   *rules* changed, or `server.js` skill-serving semantics changed) are invisible
   to the diff and to the test suite — they are a **human judgement call** and are
   explicitly out of this workflow's scope (see "leaves to the human").
5. **Re-adapt skills (fan-out agents)** — one transform agent per domain in
   READAPT, each fed its per-skill `git diff --no-index`. The
   `adapt-skill-for-mcp.md` flow's own Phase 2b (semantic-diff audit) and Phase 3
   (per-domain checklist) still run per the runbook; the panel below is the
   cross-cutting layer ON TOP of them, not a replacement. Then the
   **5-perspective review panel** (semantic fidelity / tool+param correctness /
   reference resolution / leak+format / identity+scope) over the full READAPT set,
   in parallel. Every perspective must PASS; ⚠️ → re-dispatch that domain's
   transform (decrements the shared repair budget), re-run only the failed
   perspective. Copy `scripts/` + `assets/` for each READAPT domain from the NEW
   clone, then confirm no orphan adapted dirs remain (runbook's `comm -13` check
   against the regenerated tree → must be empty).
6. **Offline gate** — `./scripts/test.sh` then `bash scripts/test-smoke-docker.sh`
   (the two commands named in the offline-only guardrail). On failure: repair
   within the shared 2-round budget (re-dispatch the relevant transform agent or
   fix the deterministic artifact), else abort. A `scope-coverage` failure caused
   by missing scopes is EXPECTED (see the scope guardrail) — it does not count as
   a repair and is not fixed here.
7. **Draft PR** — commit the runbook's file set, push, `gh pr create --draft`
   with a body in the established style: 中文为主，按主题分块，含「上游变更亮点」
   (link the release tag) + 「变更清单」+ any ⚠️ scope/identity notes. Model the
   structure on the merged bump PRs (#88/#87). Then STOP and report the PR URL.

## What it explicitly leaves to the human

- Reviewing the re-adapted skills' semantic fidelity (panel is a filter, not a
  guarantee).
- Deciding a **full re-adapt** is needed (adapt rules or `server.js` semantics
  changed) — the automation only does the diff-guided incremental set.
- Adding/removing OAuth scopes (the workflow only flags the gap; see scope guardrail).
- Deploying the branch to any environment.
- `upgrade.sh` canary/rollout.
- Merging the PR.

## Running

Invoke via the `Workflow` tool with the inline script (authored from these
phases). Pass `args = {"old":"<OLD>","new":"<NEW>"}` from the detection output.
The script must encode the guardrails above as actual control flow, not comments:
stop-at-PR (final action is `gh pr create --draft`), a **single shared** repair
counter capped at 2 across phases 5–6, the offline gate as exactly
`./scripts/test.sh` + `bash scripts/test-smoke-docker.sh`, and the scope-coverage
failure treated as expected (PR drafted with ⚠️, not repaired) when scopes are missing.
