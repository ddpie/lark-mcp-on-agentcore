[中文](security_zh.md) | [English](security_en.md)

# 安全

## 概述

本系统采用纵深防御策略，在网络边缘、传输层、应用层和存储层都实施安全控制。所有 Token 永远不会离开 AWS 内网，OAuth 流程使用 PKCE + client_secret 双重保护，并通过 HMAC 签名防止 CSRF 和 Token 伪造。

## OAuth 2.0 PKCE 流程

系统实现了完整的 OAuth 2.0 Authorization Code + PKCE (RFC 7636) 流程：

1. **客户端生成 code_verifier**（随机字符串）和 **code_challenge**（SHA-256 哈希）
2. 客户端发起 `/authorize` 请求时必须携带 `code_challenge`（缺失则返回 400）；`code_challenge_method` 可省略，但若提供则必须为 `S256`，其他值（如 `plain`）会被拒绝
3. code_challenge 被编码进 HMAC 签名的 state 参数，随用户重定向到飞书授权页
4. 飞书授权后回调 `/callback`，系统将授权码存入 DynamoDB（含 code_challenge），生成一次性 auth code 返回客户端
5. 客户端请求 `/token` 时必须同时提供 `code_verifier` 和 `client_secret`
6. 服务端计算 `SHA256(code_verifier)` 并与存储的 code_challenge 做 base64url 比对

PKCE 防止授权码被中间人截获后直接兑换 Token — 即使攻击者拿到了授权码，没有原始 code_verifier 也无法获取 access_token。系统只接受 S256 方法，拒绝 plain 方法。

## HMAC Token 签名（域分离密钥）

系统从一个根密钥（存储在 SSM Parameter Store SecureString 中）派生出三个独立的 HMAC-SHA256 签名密钥：

```
STATE_SECRET (root, 256-bit)
  ├── HMAC(root, "oauth-state-v1")   → stateKey  (OAuth state 签名)
  ├── HMAC(root, "mcp-token-v1")     → tokenKey  (MCP Bearer Token 签名)
  └── HMAC(root, "mcp-incr-auth-v1") → incrKey   (增量授权 Token 签名)
```

**为什么域分离？** 如果三种 Token 共用同一密钥，则对某种 Token 的签名可能被用于伪造另一种 Token（oracle 攻击）。域分离确保即使攻击者能观察到 state 签名的输出，也无法推导出 MCP Token 签名密钥。

**OAuth State 签名格式：** `base64url(payload).timestamp.hmac_hex`
- payload 编码了 redirect_uri、client state、code_challenge 等
- timestamp 用于 5 分钟过期检查
- 验证时使用 `timingSafeEqual` 防止时序攻击

**MCP Token 签名格式：** `base64url(userId:expiresAt:hmac_hex)`
- 30 天有效期
- Middleware 每次请求都验证签名和过期时间
- 验证失败时区分具体原因并记录日志（expired / signature_mismatch / malformed_payload / decode_error）

**增量授权 Token：** 用于安全地将用户 ID 传递给 `/authorize` 端点的增量授权流程。直接在 URL 中暴露 user_id 会导致 confused-deputy 攻击（攻击者诱骗受害者在攻击者选择的 ID 下授权），因此增量授权 Token 使用独立密钥签名，有效期仅 5 分钟。

## Write-Probe 机制（Token 刷新前预检）

飞书的 refresh_token 是**一次性**的 — 使用后即失效，新的 refresh_token 在响应中返回。这意味着如果刷新成功但存储失败，用户的 Token 将永久丢失。

为防止这种灾难性场景，系统在每次刷新前执行"写探针"（preflight write-probe）：

```
1. 读取当前 Secret 值
2. 将相同值写回（PutSecretValue，幂等操作）
3. 如果写入成功 → SM 可写，继续刷新
4. 如果写入失败 → SM 不可写（限流/网络故障等），跳过本轮刷新
```

跳过刷新时，refresh_token 不会被消耗，下一个 30 分钟周期 SM 恢复后可以正常刷新。只有在 write-probe 通过后才会调用飞书 refresh API。

如果刷新成功但后续存储仍然失败（极端情况），系统会以指数退避重试最多 5 次。5 次全部失败则记录 CRITICAL 级别日志 `store_token_lost`，触发最高优先级告警。

## WAF 规则

WAFv2 部署在 us-east-1（CloudFront scope），可选启用（部署时交互询问，默认关闭）：

| 规则 | 优先级 | 限制 | 作用 |
|------|--------|------|------|
| rate-limit-authorize | 1 | 100 请求/5分钟/IP | 防止对 `/authorize` 的暴力攻击（OAuth 发起端点） |
| rate-limit-global | 2 | 2000 请求/5分钟/IP | 防止 bot 爬取和泛洪攻击整个站点 |

两个规则都使用 IP 聚合，超限后返回 403 Block。WAF 启用 CloudWatch 指标和请求采样，可在 AWS 控制台查看被拦截的请求详情。

禁用 WAF 时不会产生任何费用。如果之前启用了 WAF，重新部署时选择禁用，deploy.sh 会自动销毁 us-east-1 的 WAF stack。

## Webhook 签名验证

告警 Webhook 推送到飞书群机器人时支持两种安全验证：

**签名验证（HMAC-SHA256）：**
```
timestamp = Math.floor(Date.now() / 1000)
stringToSign = "${timestamp}\n${secret}"
sign = HMAC-SHA256(stringToSign, "").digest("base64")
```
将 `timestamp` 和 `sign` 字段附加到消息 JSON 中。飞书服务端会用相同算法验证签名，拒绝伪造请求。

**关键词验证：** 消息标题中包含配置的关键词（以 `[keyword]` 格式），飞书端检查消息内容是否包含该关键词，不包含则拒收。

两种方式可以同时使用，在部署时通过交互式提示配置，保存在 `.local/deploy-config` 中。

## Token 刷新周期（30 分钟）

EventBridge 每 30 分钟触发一次 Token 刷新 Lambda。选择 30 分钟的原因：

1. **飞书 access_token 有效期为 2 小时** — 30 分钟刷新间隔意味着 Token 在剩余不到一半有效期时刷新，保证用户始终有一个可用的 access_token
2. **刷新条件**：`remaining < totalTtl / 2` — 只有 Token 剩余有效期不到总有效期一半时才刷新，避免不必要的 refresh_token 消耗
3. **并发控制**：每次最多 5 个用户并行刷新（`CONCURRENCY = 5`），防止大量用户同时刷新导致飞书 API 限流
4. **成本考量**：每 30 分钟一次 Lambda 调用，月成本可忽略不计（约 60 * 24 * 30 = 43,200 次/月，全在免费额度内）

## 安全层面汇总

| 层面 | 措施 |
|------|------|
| Token 存储 | Secrets Manager（默认使用 AWS 托管的 `aws/secretsmanager` KMS 密钥加密；当前未支持客户自管 KMS / BYOK；所有读写经 CloudTrail 审计） |
| Token 传输 | AWS 内网 TLS + SigV4，不经过公网 |
| OAuth 防 CSRF | HMAC-SHA256 签名 state（timing-safe，5 分钟过期） |
| MCP 认证 | OAuth 2.0 (PKCE + client_secret)，HMAC 签名 token（30 天有效） |
| 容器 | 无状态 per-request，非 root 运行；SIGTERM 优雅关闭并跟踪子进程 |
| App Secret | 容器启动后异步从 Secrets Manager 拉取；加载完成前 `/ping` 健康检查返回 503、tools/call 返回 `server_initializing`，避免上线前接受流量；密钥不进 AgentCore 控制面，不出现在日志/argv |
| 边缘防护 | CloudFront；可选启用 WAFv2（部署时交互询问，默认关）|
| OAuth code | DynamoDB 存储 + TTL + ConditionExpression 防重放 |
| Token 刷新 | 调 Feishu 前 SM 写探针；写不通即跳过本轮，refresh_token 不消耗 |
| 高风险写操作 | 必须传 `_confirm: true` 才执行；默认返回 `confirmation_required` |
| 部署面 | OAuth Client Secret 等敏感值通过 `--environment file://` / `--secret-string file://` 等文件参数写入，不进 `ps auxww` |
| Redirect URI 验证 | 基于 hostname 比对（非正则），防止 x.foo.com.attacker.com 绕过 |
| 日志脱敏 | userId / open_id 以 sha256 前 16 位呈现，不记录明文 |
