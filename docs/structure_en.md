[中文](structure_zh.md) | [English](structure_en.md)

# Project Structure

```
config/
  i18n.json           i18n strings (shell/dashboard/alarm/callback)
  alarm-thresholds.json  Alarm threshold defaults (threshold/period/evaluationPeriods)
  alarm-presets.json     Alarm presets (standard/relaxed/strict)
  oauth-scopes.json   Default OAuth scopes (covers Tier1 tools)
docker/
  Dockerfile          lark-cli ARM64 container (lark-cli version pinned)
  package.json        Container runtime deps (AWS SDK)
  generate-tools.js   Build-time tool catalog + scope mapping
  shortcut-scopes.json  lark-cli command → scope mapping (from source)
  server.js           MCP server (tier1 + discover/invoke + skills + semaphore + SIGTERM)
  server-lib.js       Extracted unit-tested helpers (patchPermissionError, createSemaphore)
  tier1.json          28 high-frequency tools
  skills/             MCP-adapted Skills (transformed from lark-cli skills, served by lark_get_skill)
infra/
  lib/oauth-stack.ts  OAuth + MCP + DDB + CloudWatch (Alarms + Dashboard + Webhook) + CloudFront
  lib/runtime-stack.ts  Docker image + IAM (with SM read access)
  lib/waf-stack.ts    CloudFront-scope WAFv2 (us-east-1, optional)
lambda/
  token-refresh-shim/ OAuth flow + token refresh (preflight + retry)
                      __tests__/        Unit tests (vitest)
                      dynamodb-codes.ts OAuth code temp store
                      dynamodb-openid.ts OpenID→userId mapping (DynamoDB)
  mcp-middleware/     Token verification + SigV4 proxy + 25s timeout
  alarm-webhook/      SNS → Feishu webhook (message card formatting)
scripts/
  deploy.sh           Interactive deployment (Chinese/English, optional WAF cross-region bootstrap)
  install.sh          One-click install (Chinese/English)
  ops.sh              Operations toolkit (status/list-users/revoke/refresh-all/logs/rotate-secret/destroy)
  teardown.sh         Full destroy (Runtime + CDK stacks + WAF if enabled + optional user-token cleanup)
  test.sh             Unified test entry (unit / coverage / mutation / audit / e2e)
  test-e2e.sh         End-to-end tests (OAuth + Runtime + /mcp + WAF if enabled)
  audit-tools.sh      Tool catalog structural audit (15 assertions, with snapshot)
  audit-deps.sh       Multi-dir npm audit
  check-lark-cli-version.sh  Dockerfile / scope-map version drift check
  build-scope-allowlist.sh   Regenerate OAuth scope allowlist
```

docs/skills/  (runbooks for AI-assisted maintenance)
  bump-lark-cli.md       lark-cli version upgrade runbook (extraction strategy + steps)
  adapt-skill-for-mcp.md  rules for transforming lark-cli skills into MCP form

.local/ (gitignored, per-deployment state)
  deploy-config            Deploy configuration memory
  alarm-thresholds.json    User-customized alarm thresholds
  deploy-output.md         Deployment output info
