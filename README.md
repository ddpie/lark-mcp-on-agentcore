# lark-mcp-on-agentcore

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![lark-cli](https://img.shields.io/badge/lark--cli-pinned-blue)](https://github.com/larksuite/cli)
[![AgentCore](https://img.shields.io/badge/AWS-Bedrock%20AgentCore-orange)](https://aws.amazon.com/bedrock/agentcore/)

[中文](#lark-mcp-on-agentcore) | [English](#english)

将 200+ 飞书 API 部署为远程 MCP 服务，为 [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/) 提供飞书工具能力。连接后，用户可通过自然语言完成发消息、管日程、读写多维表格等操作。基于 AWS Bedrock AgentCore 托管，支持多用户 OAuth 身份隔离、自动弹性伸缩（空闲缩零）、可观测性（5 板块 Dashboard + 10 项告警 + 飞书群通知）。API 协议层完全委托 [lark-cli](https://github.com/larksuite/cli)，飞书新增 API 时只需更新 Dockerfile 中的 lark-cli 版本并重新部署，无需修改业务代码。

## 效果

在 [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/) 中连接后，用自然语言操作飞书：

<p align="center">
  <img src="docs/images/quick-desktop-demo.png" alt="Demo" width="720">
</p>

```
> 帮我查一下今天的飞书日程
> 发一条消息给产品研发群：明天下午3点对齐需求
> 把上周的会议纪要整理成文档发给我
> 在多维表格里新增一条 Bug 记录
```

所有操作以用户自己的飞书身份执行，数据按用户隔离。

## 部署

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)
```

全程交互式引导（箭头键选择，不用输数字）：

检查依赖 → 飞书凭证 → 区域 / WAF / 日志保留 / 告警预设 / Webhook → 确认 → 自动部署

> macOS / Linux 均兼容。重复部署自动记忆上次配置，直接回车保留。

## 架构

用户通过 Quick Desktop 发起请求 → CloudFront → API Gateway → Middleware Lambda（验证 MCP Token + SigV4 签名）→ AgentCore Runtime（lark-cli 容器处理飞书 API 调用）。OAuth Lambda 负责用户授权和 Token 自动刷新（每 30 分钟），EventBridge 定时触发。所有 Token 加密存储在 Secrets Manager 中。

<p align="center">
  <img src="docs/images/architecture.svg" alt="Architecture" width="720">
</p>

<details>
<summary>组件一览</summary>

| 类别 | 组件 | 说明 |
|---|---|---|
| 计算 | AgentCore Runtime | MCP 服务容器，无状态，自动弹性，空闲缩零 |
| 计算 | Lambda × 3 | OAuth 流程 + MCP 代理 + 告警转发（告警转发 Lambda 仅在配置 webhook 时创建） |
| 边缘 | CloudFront | HTTPS 入口；可选 WAFv2 速率限制 |
| 可观测 | CloudWatch | Dashboard（5 板块 / 12 图表）+ 10 Alarms → SNS → 飞书群 |
| 状态 | SM + DDB + SSM | Token 加密存储 + Auth Code + 签名密钥 |

</details>

## 特点

| | 说明 |
|---|---|
| **200+ 工具** | 28 个高频工具直接提供，其余通过 `lark_discover` / `lark_invoke` 按需调用 |
| **多用户** | 多用户共享一个部署，per-user OAuth 身份隔离 |
| **低运维** | Token 自动刷新（30min）、异常自动告警到飞书群、日志按策略过期 |
| **安全** | PKCE + HMAC token + WAF + Secrets Manager 加密存储（[详情](docs/security_zh.md)） |
| **轻量升级** | lark-cli 新版本发布时，改 Dockerfile 版本号 → 重新 `deploy.sh`，终端用户无需任何操作 |

## 文档

| 主题 | 链接 |
|------|------|
| Quick Desktop 配置（图文 6 步） | [docs/quick-desktop-setup_zh.md](docs/quick-desktop-setup_zh.md) |
| 安全设计 | [docs/security_zh.md](docs/security_zh.md) |
| 可观测性 & 告警 | [docs/observability_zh.md](docs/observability_zh.md) |
| 运维 & 命令 | [docs/operations_zh.md](docs/operations_zh.md) |
| 常见问题 | [docs/faq_zh.md](docs/faq_zh.md) |
| 成本估算 | [docs/cost_zh.md](docs/cost_zh.md) |
| 项目结构 | [docs/structure_zh.md](docs/structure_zh.md) |

## 快速命令

```bash
./scripts/deploy.sh          # 部署 / 更新
./scripts/ops.sh status      # 系统状态
./scripts/ops.sh list-users  # 已授权用户
./scripts/ops.sh logs        # Lambda 日志
./scripts/teardown.sh        # 销毁所有资源
```

## License

MIT

---

# English

Deploy 200+ Feishu APIs as a remote MCP service for [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/). Once connected, users send messages, manage calendars, read/write Bitable, and more through natural language. Hosted on AWS Bedrock AgentCore with multi-user OAuth isolation, auto-scaling (scale-to-zero), and observability (5-section dashboard + 10 alarms + Feishu group notifications). API layer fully delegated to [lark-cli](https://github.com/larksuite/cli) — when Feishu adds new APIs, just bump the lark-cli version in Dockerfile and re-deploy. No application code changes.

## What it looks like

Connect in [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/) and interact with Feishu using natural language:

<p align="center">
  <img src="docs/images/quick-desktop-demo-en.png" alt="Demo" width="720">
</p>

```
> Check my Feishu calendar for today
> Send a message to the product dev group: sync requirements tomorrow at 3pm
> Summarize last week's meeting notes into a doc
> Add a bug record to the Bitable
```

Every action runs under the user's own Feishu identity — data is isolated per user.

## Deploy

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)
```

Fully interactive (arrow-key selection, no numbers to type):

Check deps → Feishu credentials → Region / WAF / Log retention / Alarm presets / Webhook → Confirm → Auto deploy

> Compatible with macOS and Linux. Re-deploys remember previous config — just press Enter to keep.

## Architecture

User requests from Quick Desktop → CloudFront → API Gateway → Middleware Lambda (MCP token verification + SigV4 signing) → AgentCore Runtime (lark-cli container handles Feishu API calls). OAuth Lambda manages user authorization and auto-refreshes tokens every 30 minutes via EventBridge. All tokens encrypted in Secrets Manager.

<p align="center">
  <img src="docs/images/architecture-en.svg" alt="Architecture" width="720">
</p>

<details>
<summary>Components</summary>

| Category | Component | Description |
|---|---|---|
| Compute | AgentCore Runtime | MCP service container, stateless, auto-scaling, scale-to-zero |
| Compute | Lambda × 3 | OAuth flow + MCP proxy + alarm relay (the alarm-relay Lambda is created only when a webhook is configured) |
| Edge | CloudFront | HTTPS entry; optional WAFv2 rate limiting |
| Observability | CloudWatch | Dashboard (5 sections / 12 charts) + 10 Alarms → SNS → Feishu group |
| State | SM + DDB + SSM | Encrypted tokens + Auth codes + Signing keys |

</details>

## Highlights

| | Description |
|---|---|
| **200+ tools** | 28 high-frequency tools exposed directly; the rest reachable via `lark_discover` / `lark_invoke` on demand |
| **Multi-user** | Shared deployment with per-user OAuth identity isolation |
| **Low-ops** | Auto token refresh (30min), alarms auto-push to Feishu group, logs expire by policy — no daily manual intervention |
| **Secure** | PKCE + HMAC tokens + WAF + Secrets Manager encryption ([details](docs/security_en.md)) |
| **Lightweight upgrade** | When lark-cli releases a new version, bump Dockerfile → re-run `deploy.sh`, end users need no action |

## Docs

| Topic | Link |
|-------|------|
| Quick Desktop Setup (6 steps, screenshots) | [docs/quick-desktop-setup_en.md](docs/quick-desktop-setup_en.md) |
| Security | [docs/security_en.md](docs/security_en.md) |
| Observability & Alarms | [docs/observability_en.md](docs/observability_en.md) |
| Operations & Commands | [docs/operations_en.md](docs/operations_en.md) |
| FAQ | [docs/faq_en.md](docs/faq_en.md) |
| Cost | [docs/cost_en.md](docs/cost_en.md) |
| Project Structure | [docs/structure_en.md](docs/structure_en.md) |

## Quick Commands

```bash
./scripts/deploy.sh          # Deploy / update
./scripts/ops.sh status      # System status
./scripts/ops.sh list-users  # Authorized users
./scripts/ops.sh logs        # Lambda logs
./scripts/teardown.sh        # Destroy all resources
```

## License

MIT
