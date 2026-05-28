[中文](faq_zh.md) | [English](faq_en.md)

# 常见问题

**Q: Quick Desktop 连接时认证失败？**

A: 检查飞书应用安全设置中的重定向 URL 是否包含部署输出的 Redirect URL。

**Q: 用户 30 天没使用，token 过期了？**

A: 下次连接时会自动重新触发飞书授权。

**Q: 部署失败了？**

A: 脚本支持重跑（幂等）。如需彻底重来：`cd infra && npx cdk destroy --all`。

**Q: 如何限制哪些用户可以使用？**

A: 飞书应用的「可用范围」控制。只有范围内的用户才能完成 OAuth 授权。

**Q: Quick Desktop 显示 "Creation failed"？**

A: 检查两点：1) 飞书应用安全设置中是否添加了部署输出的 Redirect URL；2) Client Secret 是否与部署输出一致（如不确定可运行 `./scripts/ops.sh rotate-secret` 重新生成）。

**Q: 如何更新 lark-cli 版本？**

A: 按 `docs/skills/bump-lark-cli.md` 流程操作（提取 scope → 适配 Skill → deploy），或直接 `./scripts/deploy.sh --yes` 非交互部署。终端用户无需任何操作。

**Q: 轮换 Client Secret 后，已有用户需要重新授权吗？**

A: 不需要。`./scripts/ops.sh rotate-secret` 只更新 OAuth Client Secret（用于 Quick Desktop 在 `/token` 端点兑换 code 时校验），已发放的 MCP Bearer Token 仍然有效（这些 Token 由 SSM 中的 `STATE_SECRET` 派生的密钥签名，未发生变化）。但需要在 Quick Desktop connector 中更新 Client Secret，否则下一次需要兑换 code 时会失败。如需让所有 MCP Token 立即失效，应轮换 SSM 中的 `/lark-mcp-on-agentcore/state-secret`（会同时使 OAuth state 与 MCP Token 失效，需所有用户重新连接）。

升级 lark-cli 版本不影响已有用户。

**Q: 调用 API 报权限不足（如日历、消息搜索等）？**

A: 这是飞书应用的权限配置问题，不是客户端问题。解决方法：

1. 进入 [飞书开放平台](https://open.feishu.cn/app) → 你的应用 → **权限管理**
2. 搜索并开通所需权限（常见的如下表）
3. **重新发布应用版本**（权限变更需要发版才生效）
4. 用户无需重新授权——下次调用时权限自动生效

| 功能 | 所需权限 |
|------|---------|
| 读取日历/日程 | `calendar:calendar:read`、`calendar:calendar.event:read` |
| 搜索/读取消息 | `im:message:read`、`im:chat:read` |
| 发送消息 | `im:message:send_as_user` |
| 读取群聊列表 | `im:chat:read` |
| 搜索文档 | `drive:drive:read` |
| 读写多维表格 | `bitable:bitable:read`、`bitable:bitable:write` |

> 如果管理员在开放平台新增了 API 权限并发版，**之前已连接过的用户**不会自动获得新权限。需要重连，步骤：Quick Desktop → Settings → Capabilities → 最下方 Browse Connections → 搜索找到 Feishu Remote MCP → 点击卡片 → 点击 Test action APIs → 弹出页面右侧点击 Re-Connect → 弹出飞书授权页完成授权。

**Q: 收到 TokenLost 告警（store_token_lost）该怎么处理？**

A: 这是最严重的告警，意味着用户的 refresh_token 已被消耗但新 Token 写入 Secrets Manager 失败（5 次重试全部失败），该用户需要重新授权。处置步骤：

1. 在告警卡片或日志中找到 `userIdHash`（sha256 前 16 位）。**所有日志（包括 `oauth_callback_success`）只记录 hash，不含原始 user_id**（脱敏设计）。如需运行 `revoke`，运行 `aws secretsmanager list-secrets --filters Key=name,Values=lark-mcp-on-agentcore/users/` 列出所有用户名（路径末段即 user_id），逐个计算 sha256 前 16 位与告警 hash 比对
2. 通知该用户在 Quick Desktop 中重新连接（Settings → Capabilities → Connections → 找到 feishu → Sign in 重新授权）。重连时 OAuth 回调会通过 openid-map 映射（如果存在）或回退到同一飞书 `open_id` 复用 stable userId，最终调用 `CreateSecret` 重建用户 Secret
3. （可选）如需主动清理残留 Secret：`./scripts/ops.sh revoke <user_id>`。注意 `revoke` 仅删除 user secret，保留 openid-map 映射，因此用户重新授权后 stable userId 不变
4. 检查 CloudWatch Logs 中 `event=store_token_lost` 的上下文，常见根因：Secrets Manager 限流、IAM 权限被改、KMS 密钥不可用

```
fields @timestamp, userIdHash, error, refresh_token_consumed
| filter event = "store_token_lost"
| sort @timestamp desc
```

**Q: 调用低频工具时提示权限不足？**

A: 系统会自动检测缺失的权限并生成增量授权链接。用户点击链接，在飞书授权页确认新增权限即可（无需重新授权全部权限，飞书会累积已有权限）。

**Q: 支持哪些 AWS 区域？**

A: 取决于 AWS Bedrock AgentCore 的可用区域。部署脚本提供了常用区域选择。

**Q: 支持自定义域名吗？**

A: 支持。部署时脚本会提示输入自定义域名，或设置环境变量 `CUSTOM_DOMAIN=mcp.company.com`。

**Q: 支持国际版 Lark 吗？**

A: 支持。部署时设置环境变量 `LARKSUITE_CLI_BRAND=lark`。

**Q: 重复部署时需要重新输入所有配置吗？**

A: 不需要。所有配置（区域、语言、域名、WAF、日志保留天数、飞书凭证、Webhook URL）都会自动记忆。重新运行 `deploy.sh` 时直接回车即可保留上次选择。

**Q: 怎么配置告警通知？**

A: 部署时脚本会提示输入飞书群 Webhook URL。创建步骤：

1. 打开飞书，进入接收告警的群聊
2. 群设置（右上角 ⚙️）→ 群机器人 → 添加机器人
3. 选择「自定义机器人」→ 输入名称（如 "MCP 告警"）→ 下一步
4. 复制 **Webhook URL**（格式：`https://open.feishu.cn/open-apis/bot/v2/hook/xxx`）
5. 粘贴到部署脚本的提示中

可选安全配置：脚本还会提示输入**签名密钥**（HMAC 验证）和**关键词**（消息必须包含），两项均为可选但生产环境建议开启。

配置后，所有 CloudWatch 告警会以消息卡片推送到群聊。也可以后续通过 `aws sns subscribe` 订阅邮箱或其他渠道。

**Q: 怎么查看监控看板？**

A: 部署完成后会输出 Dashboard URL。也可以在 AWS CloudWatch 控制台搜索 `lark-mcp-on-agentcore` 看板。看板包含 5 个分区：告警状态、流量、Lambda、OAuth/Token、基础设施。

**Q: 日志保留多久？会一直累积吗？**

A: 部署时可选择保留天数（30/90/180/365/永不过期，默认 90 天）。超过保留期的日志自动删除，不会无限累积存储费用。

**Q: AgentCore Runtime 空闲回收时长怎么配置？**

A: 部署时可选 5/10/15/30 分钟（默认 10 分钟）。该值决定 session 静默多久后容器被回收。回收后下次请求会触发冷启动（首次容器拉起需要数秒到十几秒）。

权衡：
- **5 分钟**：用户量小、成本敏感；冷启动较频繁
- **10 分钟（推荐）**：覆盖典型对话 burst，比 AWS 默认 15 分钟节省 ~30% idle 成本
- **15 分钟**：AWS 默认值
- **30 分钟**：用户连续多次提问、对延迟敏感的场景

配置保存在 `.local/deploy-config` 的 `AGENTCORE_IDLE_TIMEOUT`，重新运行 `deploy.sh` 可修改。也可以通过环境变量 `AGENTCORE_IDLE_TIMEOUT=300 ./scripts/deploy.sh` 覆盖。

**Q: 怎么自定义告警阈值？**

A: 部署时提供三个预设（标准/宽松/严格），箭头选择即可应用。如需逐项调整，选"自定义"后箭头选择要修改的告警，会展示含义和建议范围。自定义值保存在 `.local/alarm-thresholds.json`（不进 git），后续 deploy 不会覆盖。
