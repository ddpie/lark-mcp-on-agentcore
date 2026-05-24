[中文](operations_zh.md) | [English](operations_en.md)

# Operations

## Command Reference

### `./scripts/ops.sh`

| Subcommand | Description | Details |
|-----------|-------------|---------|
| `status` | System overview | Shows authorized user count and EventBridge token refresh rule status (ENABLED/DISABLED) |
| `list-users` | List authorized users | Calls `secretsmanager list-secrets` to list all secrets under `lark-mcp-on-agentcore/users/` (with name and last-updated time) |
| `revoke <user_id>` | Revoke user authorization | After interactive confirmation, force-deletes the user's secret (`--force-delete-without-recovery`); their MCP and Feishu tokens are immediately invalidated |
| `rotate-secret` | Rotate OAuth Client Secret | Generates new 256-bit hex secret -> writes to SSM -> updates OAuth Lambda env vars. **Note**: existing MCP tokens remain valid (STATE_SECRET unchanged), but Quick Desktop connector must be updated with new Client Secret |
| `refresh-all` | Manually trigger token refresh | Directly invokes OAuth Lambda with `{"source":"aws.events"}` to simulate EventBridge, outputs JSON result (refreshed/failed/skipped/total) |
| `logs` | View Lambda logs | Uses `aws logs tail` to show OAuth Lambda logs from the last hour (last 20 lines) |
| `destroy` | Delete AgentCore Runtime | Only deletes Runtime + Endpoint (non-CDK resources); does not destroy infrastructure. For full teardown use `teardown.sh` |
| `help` | Show help | Lists all available commands |

### `./scripts/deploy.sh` Deployment Flow

deploy.sh is an interactive deployment script handling the full flow from environment checks to end-to-end verification:

**Step 0: Environment Checks**
- Verifies bash version (4+ required; macOS auto-upgrades via Homebrew)
- Validates node, docker, aws, python3 availability
- Checks Docker is running (auto-starts on macOS)
- Verifies `boto3` Python package is installed
- Validates AWS credentials (`aws sts get-caller-identity`)

**Configuration Collection (interactive):**
1. Language selection (Chinese/English)
2. Feishu App ID + App Secret (supports env vars `FEISHU_APP_ID`/`FEISHU_APP_SECRET`, detects and reuses existing credentials)
3. Validates credentials against Feishu API
4. Custom domain (optional)
5. WAF enable/disable
6. Log retention days (30/90/180/365/never expire)
7. Alarm threshold preset selection (Standard/Relaxed/Strict/Custom)
8. Feishu alarm webhook URL + signature secret + keyword
9. Deploy region selection

**Step 1/5: CDK Deploy**
- Creates/updates Feishu app credentials in Secrets Manager
- Creates SSM SecureStrings: state-secret (signing root key) and oauth-client-secret
- Installs dependencies (root + docker + infra)
- `cdk deploy` deploys Runtime Stack + WAF Stack (optional) + OAuth Stack

**Step 2/5: AgentCore Runtime**
- Uses boto3 to create or update AgentCore Runtime (container image URI, IAM Role, environment variables)
- Polls until Runtime status becomes READY (up to 5 minutes)

**Step 3/5: Runtime Endpoint**
- Creates or updates Runtime Endpoint
- Polls until Endpoint is ready

**Step 4/5: Configure Middleware**
- Updates Middleware Lambda environment variables (RUNTIME_ARN, AUTHORIZE_BASE, etc.)

**Step 5/5: Verification**
- HTTP request to `/.well-known/oauth-authorization-server` to verify OAuth is reachable
- SigV4 call to AgentCore Runtime to verify MCP protocol response

**Post-deploy:**
- Saves configuration to `.local/deploy-config`
- Saves full deployment info (including OAuth Client Secret) to `.local/deploy-output.md`
- Outputs next steps (configure Feishu redirect URL + Quick Desktop connector)

### `./scripts/teardown.sh` Teardown Flow

Completely destroys all deployed resources in dependency-safe order:

1. **AgentCore Runtime**: Delete Endpoint -> wait 3s -> Delete Runtime
2. **CDK stacks** (deploy region): Destroy LarkMcpOnAgentCoreOAuth + LarkMcpOnAgentCoreRuntime
3. **WAF stack** (us-east-1): Destroy LarkMcpOnAgentCoreWaf (if SKIP_WAF!=1)
4. **User tokens**: Lists all user secrets, batch-deletes after interactive confirmation (`--force-delete-without-recovery`)
5. **Preserved resources** (not auto-deleted, manual cleanup commands provided):
   - `lark-mcp-on-agentcore/feishu-app` Secret
   - `/lark-mcp-on-agentcore/state-secret` SSM
   - `/lark-mcp-on-agentcore/oauth-client-secret` SSM
   - `lark-mcp-on-agentcore/openid-map/*` Secrets

Use `TEARDOWN_YES=1` to skip top-level confirmation (CI/CD scenarios).

## `.local/` Configuration Persistence

The `.local/` directory is in `.gitignore` and stores local deployment state:

| File | Permissions | Purpose |
|------|------------|---------|
| `.local/deploy-config` | 600 | Deploy parameters (language, region, WAF toggle, log retention, webhook secret/keyword) |
| `.local/deploy-output.md` | 600 | Full deployment info including OAuth Client Secret (sensitive!) |
| `.local/alarm-thresholds.json` | 600 | Custom alarm threshold overrides |

**How it works:** Each `deploy.sh` run reads `.local/deploy-config` for previous choices as defaults. Users can keep or modify existing settings. This means:
- First deploy: all configuration collected from scratch
- Subsequent deploys: only confirm or modify existing config, greatly reducing interaction
- Environment variables take priority over saved configuration

## Log Viewing

### Quick View

```bash
# Last hour of OAuth Lambda logs
./scripts/ops.sh logs

# Custom time range
aws logs tail "/aws/lambda/<OAuthFunctionName>" --region <region> --since 2h --format short
```

### CloudWatch Insights Queries

In the AWS Console CloudWatch Insights, select the appropriate Log Group and run queries:

```
# View all refresh failures
fields @timestamp, @message
| filter event = "refresh_cycle" and failed > 0
| sort @timestamp desc
| limit 50

# View token loss events (most urgent)
fields @timestamp, userIdHash, error, refresh_token_consumed
| filter event = "store_token_lost"
| sort @timestamp desc

# View slow calls (Feishu API > 3s)
fields @timestamp, api, durationMs
| filter event = "feishu_slow"
| sort durationMs desc
| limit 20

# Auth failure analysis
fields @timestamp, reason, userIdHash, hasBearer
| filter event in ["token_verify_failed", "auth_missing_or_invalid"]
| stats count() by reason
| sort count desc

# MCP request latency distribution
fields @timestamp, durationMs, status
| filter event = "mcp_request_ok"
| stats avg(durationMs) as avg_ms, pct(durationMs, 95) as p95_ms, pct(durationMs, 99) as p99_ms by bin(5m)

# OAuth funnel conversion
fields @timestamp, event
| filter event in ["oauth_authorize_start", "oauth_callback_success", "new_user_authorized"]
| stats count() by event
```

## Troubleshooting

### OAuth authorization succeeds but Quick Desktop shows "invalid_client"

**Cause:** Client Secret in the Quick Desktop connector does not match the one generated during deploy.

**Diagnose:**
```bash
# View current OAuth Client Secret
aws ssm get-parameter --name /lark-mcp-on-agentcore/oauth-client-secret \
  --with-decryption --query 'Parameter.Value' --output text --region <region>
```

**Fix:** Update the Quick Desktop connector's Client Secret field with the output value.

### Token refresh shows all "skipped"

**Cause:** Secrets Manager temporarily non-writable (throttled or network issue); the write-probe mechanism protected refresh_tokens from being consumed.

**Diagnose:**
```bash
# Manually trigger refresh and check detailed results
./scripts/ops.sh refresh-all
```

If persistently skipped, check that the Lambda's IAM Role has `secretsmanager:PutSecretValue` permission.

### Users report "feishu_not_authorized"

**Possible causes:**
1. User's Feishu token expired and refresh failed
2. Feishu app permissions were changed
3. User manually revoked authorization in Feishu

**Diagnose:**
```bash
# Check if user's secret exists
aws secretsmanager get-secret-value \
  --secret-id "lark-mcp-on-agentcore/users/<user_id>" --region <region>

# Check if expires_at has passed
```

**Fix:** User needs to re-authorize via OAuth.

### CDK deploy fails with ROLLBACK_COMPLETE

**Cause:** Previous deploy failed, leaving the stack in ROLLBACK_COMPLETE state.

**Fix:** `deploy.sh` auto-detects and cleans this state (deletes old stack then recreates). If auto-cleanup also fails:
```bash
aws cloudformation delete-stack --stack-name LarkMcpOnAgentCoreOAuth --region <region>
aws cloudformation wait stack-delete-complete --stack-name LarkMcpOnAgentCoreOAuth --region <region>
```

### High MCP request latency

**Diagnosis steps:**
1. Check the Dashboard "MCP Traffic" section latency graph — determine if P95 or Average is elevated
2. Check if AgentCoreSlow / FeishuSlow in the "Errors" graph correlate
3. If AgentCoreSlow: likely Runtime container cold start, should recover within minutes
4. If FeishuSlow: Feishu API-side issue, check Feishu service status

## Test Commands

```bash
./scripts/test.sh                  # Unified test entry (default: unit + typecheck + lint)
./scripts/test.sh --coverage       # Unit tests + coverage report
./scripts/test.sh --mutation       # Stryker mutation testing (~7min)
./scripts/test.sh --smoke          # Docker container smoke test (health + protocol)
./scripts/test.sh --mcp-protocol   # MCP protocol compliance validation (needs Docker + jq)
./scripts/test.sh --full           # All tiers including smoke + audit + e2e
./scripts/test-e2e.sh              # End-to-end test (OAuth, Runtime, /mcp, WAF)
./scripts/audit-tools.sh           # Tool catalog structural audit (15 assertions)
./scripts/audit-deps.sh            # npm audit (root + docker + infra)
./scripts/check-lark-cli-version.sh  # Detect drift between Dockerfile and scope map

npm test                           # Run vitest unit tests
npm run lint                       # ESLint (source code)
npm run knip                       # Dead code / unused dependency detection
```

## Teardown

```bash
./scripts/teardown.sh              # Destroy everything (AgentCore Runtime + cross-region WAF + CDK stacks)
```
