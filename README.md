# lark-mcp-on-agentcore

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![lark-cli](https://img.shields.io/badge/lark--cli-pinned-blue)](https://github.com/larksuite/cli)
[![AgentCore](https://img.shields.io/badge/AWS-Bedrock%20AgentCore-orange)](https://aws.amazon.com/bedrock/agentcore/)

[中文](#lark-mcp-on-agentcore) | [English](#english)

为 [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/) 提供飞书工具能力的远程 MCP 服务，开箱即用 200+ 工具（覆盖飞书 2500+ API）。连接后，用户可通过自然语言完成发消息、管日程、读写多维表格等操作。基于 AWS Bedrock AgentCore 托管，支持多用户 OAuth 身份隔离、自动弹性伸缩（空闲缩零）、可观测性（5 板块 Dashboard + 10 项告警 + 飞书群通知）。

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

检查依赖 → 飞书凭证 → 区域 / WAF / 日志保留 / 告警预设 / Webhook → 确认 → 自动部署

> 重复部署或升级版本时自动填入上次配置，按需修改。

## 架构

用户通过 Quick Desktop 发起请求 → CloudFront → API Gateway → Middleware Lambda（验证 MCP Token + SigV4 签名）→ AgentCore Runtime（MCP 服务容器处理飞书 API 调用）。OAuth Lambda 负责用户授权和 Token 自动刷新（每 30 分钟），EventBridge 定时触发。所有 Token 加密存储在 Secrets Manager 中。

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

| 特点 | 说明 |
|---|---|
| **200+ 工具** | 28 个高频工具直接提供，其余通过 `lark_discover` / `lark_invoke` 按需调用 |
| **多用户** | 一份部署多人共用，每位用户以自己飞书身份调用 |
| **按需付费** | AgentCore Runtime 空闲缩零，按 vCPU-秒 + 内存-秒计费 |
| **渐进授权** | 调用低频工具触发飞书未授权时，自动生成 incremental-auth 链接，用户点击链接跳转到飞书授权页确认新增权限即可，飞书会累积已有权限 |
| **低运维** | Token 自动刷新（30min）、异常自动告警到飞书群、日志按策略过期 |
| **安全** | PKCE + HMAC token + WAF + Secrets Manager 加密存储（[详情](docs/security_zh.md)） |
| **轻量升级** | lark-cli 新版本发布时，改 Dockerfile 中的 lark-cli 版本号 → 重新 `deploy.sh`，终端用户无需任何操作 |

## 工具列表

### Tier 1 高频工具（28 个，直接注册）

| 类别 | 工具 |
|------|------|
| IM (5) | 发消息、搜索消息、群列表、聊天记录、搜索群 |
| Calendar (4) | 日程概览、创建日程、查忙闲、找会议室 |
| Docs (4) | 创建、获取、搜索、编辑文档 |
| Base (4) | 获取表、查询数据、批量创建记录、搜索记录 |
| Drive (3) | 搜索、上传、下载文件 |
| Task (3) | 创建任务、我的任务、完成任务 |
| Contact (2) | 搜索用户、获取用户信息 |
| Sheets (2) | 读取、写入单元格 |
| Mail (1) | 发送邮件 |

### Meta Tools（2 个）

| 工具 | 说明 |
|------|------|
| `lark_discover` | 按关键词或分类搜索其余所有 lark-cli 命令，返回名称 + 完整参数 schema |
| `lark_invoke` | 执行 discover 找到的工具（传入 tool_name + args） |

高频操作直接调用即可；其余操作 AI 会自动通过 discover 搜索再 invoke 执行，无需额外配置。

<details>
<summary>Tier 2 工具（200+，通过 discover/invoke 调用）</summary>

| 类别 | 代表功能 |
|------|----------|
| Base | 高级权限管理、复制表格、字段/表单/仪表盘 CRUD、记录导入导出 |
| Sheets | 追加行、批量样式、合并单元格、条件格式、数据验证 |
| Mail | 草稿管理、回复、转发、全部回复、模板、邮件规则 |
| Task | 指派、评论、关注者、提醒、子任务、清单管理 |
| Drive | 评论、权限申请、创建文件夹、移动/复制、导出 |
| IM | 创建群聊、更新群信息、消息回复、书签、下载附件 |
| OKR | 周期列表、目标详情、进展记录、上传图片 |
| VC | 会议搜索、入会/离会、纪要、录制、事件列表 |
| Wiki | 空间列表、节点创建/复制/移动、删除空间 |
| Docs | 媒体下载/插入/预览、批量操作 |
| Calendar | 回复邀请(RSVP)、智能时间建议、更新日程 |
| Markdown | 创建、获取、覆盖 Markdown 文件 |
| Minutes | 搜索妙记、下载音视频、上传生成妙记 |
| Slides | 创建演示文稿、上传图片、替换页面元素 |
| Whiteboard | 导出画板、更新画板内容 |

</details>

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

## 风险提示

AI Agent 以用户身份调用飞书 API 存在模型幻觉、prompt injection 等固有风险。详见 [lark-cli 安全与风险提示](https://github.com/larksuite/cli/blob/main/README.zh.md#安全与风险提示使用前必读)。

## License

MIT

---

# English

A remote Feishu MCP service for [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/), shipping 200+ tools out of the box (covering Feishu's 2500+ APIs). Once connected, users send messages, manage calendars, read/write Bitable, and more through natural language. Hosted on AWS Bedrock AgentCore with multi-user OAuth isolation, auto-scaling (scale-to-zero), and observability (5-section dashboard + 10 alarms + Feishu group notifications).

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

Check deps → Feishu credentials → Region / WAF / Log retention / Alarm presets / Webhook → Confirm → Auto deploy

> Re-deploys and upgrades pre-fill previous config; change only what you need.

## Architecture

User requests from Quick Desktop → CloudFront → API Gateway → Middleware Lambda (MCP token verification + SigV4 signing) → AgentCore Runtime (MCP service container handles Feishu API calls). OAuth Lambda manages user authorization and auto-refreshes tokens every 30 minutes via EventBridge. All tokens encrypted in Secrets Manager.

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

| Highlight | Description |
|---|---|
| **200+ tools** | 28 high-frequency tools exposed directly; the rest reachable via `lark_discover` / `lark_invoke` on demand |
| **Multi-user** | One deployment shared across users; each request runs under the user's own Feishu identity |
| **Pay-per-use** | AgentCore Runtime scales to zero when idle, billed by vCPU-seconds + memory-seconds |
| **Incremental auth** | Low-frequency tools that hit "permission denied" auto-generate an incremental-auth link; the user clicks the link, lands on the Feishu authorization page to approve the new scope, and Feishu accumulates the existing scopes |
| **Low-ops** | Auto token refresh (30min), alarms auto-push to Feishu group, logs expire by policy |
| **Secure** | PKCE + HMAC tokens + WAF + Secrets Manager encryption ([details](docs/security_en.md)) |
| **Lightweight upgrade** | When lark-cli releases a new version, bump the lark-cli version in Dockerfile → re-run `deploy.sh`, end users need no action |

## Tool List

### Tier 1 — High-Frequency Tools (28, registered directly)

| Category | Tools |
|----------|-------|
| IM (5) | Send message, search messages, list groups, chat history, search groups |
| Calendar (4) | Agenda overview, create event, check availability, find meeting rooms |
| Docs (4) | Create, fetch, search, edit documents |
| Base (4) | Get table, query records, batch create records, search records |
| Drive (3) | Search, upload, download files |
| Task (3) | Create task, my tasks, complete task |
| Contact (2) | Search user, get user info |
| Sheets (2) | Read, write cells |
| Mail (1) | Send email |

### Meta Tools (2)

| Tool | Description |
|------|-------------|
| `lark_discover` | Search all remaining lark-cli commands by keyword or category; returns name + full parameter schema |
| `lark_invoke` | Execute a tool found via discover (pass tool_name + args) |

High-frequency tools are called directly; for everything else the AI automatically discovers then invokes — no extra configuration needed.

<details>
<summary>Tier 2 — Extended Tools (200+, via discover/invoke)</summary>

| Category | Representative Features |
|----------|------------------------|
| Base | Advanced permissions, copy table, field/form/dashboard CRUD, record import/export |
| Sheets | Append rows, batch styles, merge cells, conditional formatting, data validation |
| Mail | Draft management, reply, forward, reply-all, templates, mail rules |
| Task | Assign, comment, followers, reminders, subtasks, tasklist management |
| Drive | Comments, permission requests, create folder, move/copy, export |
| IM | Create group, update group info, reply to messages, bookmarks, download attachments |
| OKR | Period list, objective details, progress records, upload images |
| VC | Meeting search, join/leave, minutes, recording, event list |
| Wiki | Space list, node create/copy/move, delete space |
| Docs | Media download/insert/preview, batch operations |
| Calendar | RSVP, smart time suggestions, update events |
| Markdown | Create, fetch, overwrite Markdown files |
| Minutes | Search minutes, download A/V, upload to generate minutes |
| Slides | Create presentation, upload images, replace page elements |
| Whiteboard | Export board, update board content |

</details>

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

## Risk Notice

Having an AI Agent operate Feishu APIs as the user carries inherent risks such as model hallucination and prompt injection. See [lark-cli Security Warnings](https://github.com/larksuite/cli/blob/main/README.md#security--risk-warnings-read-before-use).

## License

MIT
