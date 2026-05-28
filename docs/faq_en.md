[中文](faq_zh.md) | [English](faq_en.md)

# FAQ

**Q: Authentication fails when connecting from Quick Desktop?**

A: Verify the Redirect URL from deploy output is added to your Feishu app's Security Settings.

**Q: User token expired after 30 days of inactivity?**

A: Next connection automatically triggers Feishu re-authorization.

**Q: Deployment failed?**

A: The script is idempotent — just re-run. For a clean start: `cd infra && npx cdk destroy --all`.

**Q: How to restrict which users can access?**

A: Use the Feishu app's "Availability" settings. Only users in scope can complete OAuth.

**Q: Quick Desktop shows "Creation failed"?**

A: Check two things: 1) The Redirect URL from deploy output is added to your Feishu app's Security Settings; 2) The Client Secret matches the deploy output (if unsure, run `./scripts/ops.sh rotate-secret` to regenerate).

**Q: How to upgrade lark-cli?**

A: Follow `docs/skills/bump-lark-cli.md` (extract scopes → adapt Skills → deploy), or run `./scripts/deploy.sh --yes` for non-interactive deploy. End users are unaffected.

**Q: Does rotating Client Secret require users to re-authorize?**

A: No. `./scripts/ops.sh rotate-secret` only updates the OAuth Client Secret (verified by Quick Desktop when exchanging an auth code at `/token`). Issued MCP Bearer tokens remain valid because they are signed by a key derived from `STATE_SECRET` (in SSM), which does not change. You must update the Client Secret in the Quick Desktop connector — otherwise the next code-for-token exchange will fail. To invalidate all issued MCP tokens immediately, rotate `/lark-mcp-on-agentcore/state-secret` instead (this invalidates both OAuth state signatures and MCP tokens; all users must re-connect).

Upgrading lark-cli does not affect existing users.

**Q: API calls fail with "permission denied" (e.g., calendar, message search)?**

A: This is a Feishu app permission issue, not a client issue. Fix:

1. Go to [Feishu Open Platform](https://open.feishu.cn/app) → Your app → **Permissions**
2. Search and enable required permissions (common ones below)
3. **Publish a new app version** (permission changes require a new version to take effect)
4. Users do NOT need to re-authorize — permissions take effect on next API call

| Feature | Required Permission |
|---------|-------------------|
| Read calendar/events | `calendar:calendar:read`, `calendar:calendar.event:read` |
| Search/read messages | `im:message:read`, `im:chat:read` |
| Send messages | `im:message:send_as_user` |
| List chats | `im:chat:read` |
| Search docs | `drive:drive:read` |
| Read/write Bitable | `bitable:bitable:read`, `bitable:bitable:write` |

> If the admin adds new API permissions on the Open Platform and publishes a new version, **previously connected users** will not automatically gain the new permissions. Re-connection required: Quick Desktop → Settings → Capabilities → Browse Connections (bottom) → search for Feishu Remote MCP → click the card → click Test action APIs → click Re-Connect on the right side → complete Feishu authorization in the popup.

**Q: Received a TokenLost alarm (store_token_lost) — what now?**

A: This is the most severe alarm. It means a user's refresh_token was consumed but the new token failed to write to Secrets Manager (after 5 retries). The user must re-authorize. Steps:

1. Locate `userIdHash` (sha256 first-16 hex) in the alarm card or logs. **All logs (including `oauth_callback_success`) record only the hash, never the raw user_id** (intentionally redacted). To run `revoke`, list all user secrets (`aws secretsmanager list-secrets --filters Key=name,Values=lark-mcp-on-agentcore/users/`), take the trailing path segment of each as the user_id, and hash each one to find the match for the alarm's `userIdHash`
2. Ask them to reconnect in Quick Desktop: Settings → Capabilities → Connections → find feishu → Sign in. The OAuth callback reuses the same stable userId via the openid-map mapping (if one exists) or by falling back to the same Feishu `open_id`, then recreates the user secret via `CreateSecret`
3. (Optional) To proactively clean up the stale secret: `./scripts/ops.sh revoke <user_id>`. Note that `revoke` deletes only the user secret and intentionally preserves the openid-map mapping, so the user keeps the same stable userId after re-auth
4. Inspect CloudWatch Logs around `event=store_token_lost` for root cause. Common culprits: Secrets Manager throttling, IAM permission changes, KMS key unavailable

```
fields @timestamp, userIdHash, error, refresh_token_consumed
| filter event = "store_token_lost"
| sort @timestamp desc
```

**Q: Low-frequency tool returns "permission denied"?**

A: The system automatically detects the missing permission and generates an incremental authorization link. Users click the link and confirm the new permission on the Feishu authorization page (existing permissions are preserved — Feishu accumulates scopes).

**Q: Which AWS regions are supported?**

A: Depends on AWS Bedrock AgentCore availability. The deploy script offers common region choices.

**Q: Custom domain support?**

A: Yes. Set `CUSTOM_DOMAIN=mcp.company.com` or follow the deploy script prompt.

**Q: Lark (international) support?**

A: Yes. Set `LARKSUITE_CLI_BRAND=lark` during deployment.

**Q: Do I need to re-enter all config on re-deploy?**

A: No. All choices (region, language, domain, WAF, log retention, Feishu credentials, webhook URL) are remembered. Just press Enter to keep previous selections.

**Q: How to configure alarm notifications?**

A: During deploy, the script prompts for a Feishu bot webhook URL. To create one:

1. Open Feishu, enter the group chat for alerts
2. Group Settings (top-right) → Group Bots → Add Bot
3. Select "Custom Bot" → enter a name (e.g. "MCP Alerts") → Next
4. Copy the **Webhook URL** (format: `https://open.feishu.cn/open-apis/bot/v2/hook/xxx`)
5. Paste it into the deploy script prompt

Optionally configure security: the script also prompts for a **signature secret** (HMAC verification) and a **keyword** (message must contain it). Both are optional but recommended for production.

Once configured, all CloudWatch alarms are pushed as interactive message cards to the group chat. You can also subscribe email or other channels via `aws sns subscribe`.

**Q: How to view the monitoring dashboard?**

A: The deploy output includes the Dashboard URL. Or search for `lark-mcp-on-agentcore` in the AWS CloudWatch console. The dashboard has 5 sections: Alarm Status, Traffic, Lambda, OAuth/Token, and Infrastructure.

**Q: How long are logs retained?**

A: Configurable at deploy time (30/90/180/365 days or never expire, default 90). Logs beyond the retention period are automatically deleted to avoid storage cost accumulation.

**Q: How to configure the AgentCore Runtime idle session timeout?**

A: Choose at deploy time: 5/10/15/30 min (default 10 min). The value determines how long a session stays idle before the container is reclaimed. The next request after reclamation triggers a cold start (the initial container pull takes several to a dozen seconds).

Trade-off:
- **5 min**: small user base, cost-sensitive; more cold starts
- **10 min (recommended)**: covers typical conversation bursts, saves ~30% on idle cost vs the 15-min AWS default
- **15 min**: AWS default
- **30 min**: latency-sensitive scenarios where users send back-to-back queries

Persisted in `.local/deploy-config` as `AGENTCORE_IDLE_TIMEOUT`; re-run `deploy.sh` to change. You can also override via env: `AGENTCORE_IDLE_TIMEOUT=300 ./scripts/deploy.sh`.

**Q: How to customize alarm thresholds?**

A: During deploy, choose from three presets (Standard/Relaxed/Strict) using arrow keys. Or select "Custom" to pick which alarm to edit (arrow keys), with descriptions and suggested ranges shown. Custom values are saved to `.local/alarm-thresholds.json` (not committed), and subsequent deploys will not overwrite them.
