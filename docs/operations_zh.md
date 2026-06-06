[中文](operations_zh.md) | [English](operations_en.md)

# 运维

## 运维命令参考

### `./scripts/ops.sh`

| 子命令 | 说明 | 详情 |
|--------|------|------|
| `status` | 系统概览 | 显示已授权用户数、EventBridge Token 刷新规则状态（ENABLED/DISABLED） |
| `list-users` | 列出已授权用户 | 调用 `secretsmanager list-secrets` 列出 `lark-mcp-on-agentcore/users/` 下所有 Secret（含名称和最后更新时间） |
| `revoke <user_id>` | 撤销用户授权 | 交互确认后强制删除该用户的 Secret（`--force-delete-without-recovery`），用户的 MCP Token 和飞书 Token 立即失效 |
| `rotate-secret` | 轮换 OAuth Client Secret | 生成新的 256-bit hex Secret → 写入 SSM → 更新 OAuth Lambda 环境变量。**注意**：已发放的 MCP Token 仍然有效（STATE_SECRET 未变）；Amazon Quick（Quick Desktop）connector 需更新 Client Secret。自助注册客户端（Kiro、Claude Code、Codex）从不使用此 Secret，不受影响 |
| `refresh-all` | 手动触发 Token 刷新 | 直接 invoke OAuth Lambda 并传入 `{"source":"aws.events"}` 模拟 EventBridge 触发，输出 JSON 结果（refreshed/failed/skipped/total） |
| `logs` | 查看 Lambda 日志 | 使用 `aws logs tail` 显示 OAuth Lambda 最近 1 小时的日志（最后 20 行） |
| `destroy` | 删除 AgentCore Runtime | 仅删除 Runtime + Endpoint（非 CDK 管理资源），不删除基础设施。完整销毁请用 `teardown.sh` |
| `help` | 显示帮助 | 列出所有可用命令 |

### `./scripts/deploy.sh` 部署流程

deploy.sh 是一个交互式部署脚本，完成从环境检查到端到端验证的全流程：

**第 0 步：环境检查**
- 检查 bash 版本（需 4+，macOS 自动通过 Homebrew 升级）
- 验证 node、docker、aws、python3 是否可用
- 检查 Docker 是否运行（macOS 自动尝试启动）
- 验证 `boto3` Python 包是否安装
- 验证 AWS 凭证（`aws sts get-caller-identity`）

**配置收集（交互式）：**
1. 语言选择（中文/English）
2. 飞书 App ID + App Secret（支持环境变量 `FEISHU_APP_ID`/`FEISHU_APP_SECRET`，支持检测已有凭证复用）
3. 调用飞书 API 验证凭证有效性
4. 自定义域名（可选）
5. WAF 启用/禁用
6. 日志保留天数（30/90/180/365/永不过期）
7. AgentCore Runtime 空闲回收时长（5/10/15/30 分钟，默认 10 分钟）
8. 告警阈值预设选择（标准/宽松/严格/自定义）
9. 飞书告警 Webhook URL + 签名 Secret + 关键词
10. 部署区域选择

**连接 MCP 客户端（两条路径）：**
- **Kiro / Claude Code / Codex** — 自助注册（DCR），无需 secret，loopback 回调。见 [connect-mcp-clients_zh.md](connect-mcp-clients_zh.md)。
- **Amazon Quick** — 用部署输出的 Client ID + Secret 配置。见 [quick-desktop-setup_zh.md](quick-desktop-setup_zh.md)。

**第 1/5 步：CDK 部署**
- 创建/更新 Secrets Manager 中的飞书 App 凭证
- 创建 SSM SecureString：state-secret（签名根密钥）和 oauth-client-secret
- 安装依赖（root + docker + infra）
- `cdk deploy` 部署 Runtime Stack + WAF Stack (可选) + OAuth Stack

**第 2/5 步：AgentCore Runtime**
- 使用 boto3 创建或更新 AgentCore Runtime（含容器镜像 URI、IAM Role、环境变量）
- 轮询等待 Runtime 状态变为 READY（最多 5 分钟）

**第 3/5 步：Runtime Endpoint**
- 创建或更新 Runtime Endpoint
- 轮询等待 Endpoint 就绪

**第 4/5 步：配置 Middleware**
- 更新 Middleware Lambda 环境变量（RUNTIME_ARN、AUTHORIZE_BASE 等）

**第 5/5 步：验证**
- HTTP 请求 `/.well-known/oauth-authorization-server` 验证 OAuth 可达
- SigV4 调用 AgentCore Runtime 验证 MCP 协议响应

**部署后：**
- 将配置保存到 `.local/deploy-config`
- 将完整部署信息（含 OAuth Client Secret）保存到 `.local/deploy-output.md`
- 输出接下来要做的步骤（配置飞书重定向 URL + Quick Desktop connector）

### `./scripts/teardown.sh` 销毁流程

完全销毁所有部署资源，执行顺序确保无依赖冲突：

1. **AgentCore Runtime**：删除 Endpoint → 等待 3s → 删除 Runtime
2. **CDK stacks**（部署区域）：销毁 LarkMcpOnAgentCoreOAuth + LarkMcpOnAgentCoreRuntime
3. **WAF stack**（us-east-1）：销毁 LarkMcpOnAgentCoreWaf（如果 SKIP_WAF!=1）
4. **用户 Token**：列出所有用户 Secret，交互确认后批量删除（`--force-delete-without-recovery`）
5. **保留资源**（不自动删除，给出手动清理命令）：
   - `lark-mcp-on-agentcore/feishu-app` Secret
   - `/lark-mcp-on-agentcore/state-secret` SSM
   - `/lark-mcp-on-agentcore/oauth-client-secret` SSM
   - `lark-mcp-on-agentcore-openid-map` DynamoDB 表

可通过 `TEARDOWN_YES=1` 跳过顶层确认（CI/CD 场景）。

## `.local/` 配置持久化

`.local/` 目录在 `.gitignore` 中，存储当前部署的本地状态：

| 文件 | 权限 | 用途 |
|------|------|------|
| `.local/deploy-config` | 600 | 部署参数（语言、区域、WAF 开关、日志保留、空闲回收时长、Webhook Secret/Keyword） |
| `.local/deploy-output.md` | 600 | 完整部署信息含 OAuth Client Secret（敏感！） |
| `.local/alarm-thresholds.json` | 600 | 自定义告警阈值覆盖 |

**工作方式：** 每次 `deploy.sh` 运行时，会读取 `.local/deploy-config` 中上次的选择作为默认值。用户可以选择保留上次配置或修改。这意味着：
- 首次部署：所有配置从零开始收集
- 后续部署：只需确认或修改已有配置，大幅减少交互次数
- 环境变量优先级高于保存的配置

## 日志查看

### 快速查看

```bash
# 最近 1 小时 OAuth Lambda 日志
./scripts/ops.sh logs

# 指定时间段
aws logs tail "/aws/lambda/<OAuthFunctionName>" --region <region> --since 2h --format short
```

### CloudWatch Insights 查询

在 AWS 控制台 CloudWatch Insights 中，选择对应的 Log Group，执行查询：

```
# 查看所有刷新失败
fields @timestamp, @message
| filter event = "refresh_cycle" and failed > 0
| sort @timestamp desc
| limit 50

# 查看 Token 丢失事件（最紧急）
fields @timestamp, userIdHash, error, refresh_token_consumed
| filter event = "store_token_lost"
| sort @timestamp desc

# 查看慢调用（飞书 API > 3s）
fields @timestamp, api, durationMs
| filter event = "feishu_slow"
| sort durationMs desc
| limit 20

# 查看认证失败分析
fields @timestamp, reason, userIdHash, hasBearer
| filter event in ["token_verify_failed", "auth_missing_or_invalid"]
| stats count() by reason
| sort count desc

# MCP 请求延迟分布
fields @timestamp, durationMs, status
| filter event = "mcp_request_ok"
| stats avg(durationMs) as avg_ms, pct(durationMs, 95) as p95_ms, pct(durationMs, 99) as p99_ms by bin(5m)

# OAuth 漏斗转化率
fields @timestamp, event
| filter event in ["oauth_authorize_start", "oauth_callback_success", "new_user_authorized"]
| stats count() by event
```

## 常见问题排查

### OAuth 授权后 Quick Desktop 报错 "invalid_client"

**原因：** Quick Desktop connector 中填写的 Client Secret 与部署时生成的不一致。

**排查：**
```bash
# 查看当前 OAuth Client Secret
aws ssm get-parameter --name /lark-mcp-on-agentcore/oauth-client-secret \
  --with-decryption --query 'Parameter.Value' --output text --region <region>
```

**解决：** 用输出的值更新 Quick Desktop connector 的 Client Secret 字段。

### Token 刷新全部 skipped

**原因：** Secrets Manager 暂时不可写（限流或网络问题），write-probe 机制保护了 refresh_token 不被消耗。

**排查：**
```bash
# 手动触发刷新，查看详细结果
./scripts/ops.sh refresh-all
```

如果持续 skipped，检查 Lambda 的 IAM Role 是否有 `secretsmanager:PutSecretValue` 权限。

> **注意：** 用户在飞书上主动撤销授权（code 20016）也会计入 `skipped`。
> 其 secret 会被标记为计划删除（7 天恢复窗口）。如果日志中反复出现
> `user_secret_delete_failed`，请检查 Lambda 是否有 `secretsmanager:DeleteSecret` 权限。
> 用户在恢复窗口内重新授权时，secret 会自动恢复。

### 用户报告 "feishu_not_authorized"

**可能原因：**
1. 用户的飞书 Token 已过期且刷新失败
2. 飞书 App 权限被更改
3. 用户在飞书端主动取消了授权

**排查：**
```bash
# 检查该用户的 Secret 是否存在
aws secretsmanager get-secret-value \
  --secret-id "lark-mcp-on-agentcore/users/<user_id>" --region <region>

# 检查 expires_at 是否已过期
```

**解决：** 用户需要重新通过 OAuth 授权。

### CDK 部署失败 ROLLBACK_COMPLETE

**原因：** 上次部署失败后 Stack 进入 ROLLBACK_COMPLETE 状态。

**解决：** `deploy.sh` 会自动检测并清理这种状态（删除旧 Stack 后重新创建）。如果自动清理也失败：
```bash
aws cloudformation delete-stack --stack-name LarkMcpOnAgentCoreOAuth --region <region>
aws cloudformation wait stack-delete-complete --stack-name LarkMcpOnAgentCoreOAuth --region <region>
```

### MCP 请求延迟高

**排查步骤：**
1. 查看 Dashboard "MCP Traffic" 板块的延迟图，确认是 P95 还是 Average 升高
2. 查看 "Errors" 图中 AgentCoreSlow / FeishuSlow 是否同步升高
3. 如果是 AgentCoreSlow：可能是 Runtime 容器冷启动，等待几分钟后恢复
4. 如果是 FeishuSlow：飞书 API 端的问题，确认飞书服务状态

## 测试命令

```bash
./scripts/test.sh                  # 统一测试入口 (默认: unit + typecheck + lint)
./scripts/test.sh --coverage       # 单元测试 + 覆盖率报告
./scripts/test.sh --mutation       # Stryker 变异测试 (~7min)
./scripts/test.sh --smoke          # Docker 容器冒烟 (健康检查 + 协议)
./scripts/test.sh --mcp-protocol   # MCP 协议合规验证 (需 Docker + jq)
./scripts/test.sh --full           # 全部含 smoke + audit + e2e
./scripts/test-e2e.sh              # 端到端测试 (OAuth, Runtime, /mcp, WAF)
./scripts/audit-tools.sh           # 工具目录结构性自检 (15 项断言)
./scripts/audit-deps.sh            # npm audit (root + docker + infra)
./scripts/check-lark-cli-version.sh  # 检测 Dockerfile 与 scope 映射版本是否漂移

npm test                           # 运行 vitest 单元测试
npm run lint                       # ESLint (源码)
npm run knip                       # 死代码/未使用依赖检测
```

## 销毁

```bash
./scripts/teardown.sh              # 销毁所有资源（AgentCore Runtime + 跨区域 WAF + CDK stacks）
```
