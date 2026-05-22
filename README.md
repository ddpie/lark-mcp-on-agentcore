# lark-mcp-on-agentcore

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![lark-cli](https://img.shields.io/badge/lark--cli-v1.0-blue)](https://github.com/larksuite/cli)
[![AgentCore](https://img.shields.io/badge/AWS-Bedrock%20AgentCore-orange)](https://aws.amazon.com/bedrock/agentcore/)

[中文](#lark-mcp-on-agentcore) | [English](#english)

企业参考方案：将飞书/Lark 的 200+ API 部署为远程 MCP Server，基于 AWS Bedrock AgentCore，支持多用户 OAuth 认证和 per-user 身份隔离。

用户在 [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/) 中一键连接，即可用自然语言操作飞书——发消息、管日程、读写多维表格、操作文档，全部以自己的飞书身份执行。

## 示例对话

<p align="center">
  <img src="docs/quick-desktop-demo.png" alt="Demo">
</p>

```
> 帮我查一下今天的飞书日程
> 发一条消息给产品研发群：明天下午3点对齐需求
> 查一下最近 3 天的群聊记录，有哪些事情需要我跟进
```

## 运行时特点

| 特点 | 说明 |
|------|------|
| **无状态** | 每个请求独立处理，用户身份通过 header token 传递，无 session 无亲和性 |
| **自动弹性** | 并发请求增加时，AgentCore 自动拉起更多容器实例分摊负载；空闲时缩至零 |
| **升级无感** | 工具层完全复用 lark-cli，升级只需运维执行 `./scripts/deploy.sh`，终端用户无需任何操作 |

## 为什么用这个？

| | 本项目 | [lark-cli](https://github.com/larksuite/cli) | [lark-cli-mcp-wrapper](https://github.com/ddpie/lark-cli-mcp-wrapper) | [lark-openapi-mcp](https://github.com/larksuite/lark-openapi-mcp) |
|---|---|---|---|---|
| 类型 | 远程 MCP Server | CLI 工具 | 本地 MCP Server | 本地 MCP Server |
| 部署方式 | 一行命令，自托管部署 | npm install | npx 本地运行 | npx 本地运行 |
| 工具数量 | 200+ | 200+（命令行） | 200+（MCP 封装） | 19-31（preset 限制） |
| 用户身份 | per-user 隔离（OAuth） | 单用户 | 单用户 | 单用户 |
| Token 管理 | 自动获取、刷新、加密存储 | 本地 keychain | 复用 lark-cli 登录态 | 用户自己管 |
| 多用户 | 1000+ 用户共享一个部署 | N/A | N/A | N/A |
| 客户端连接 | Remote MCP + OAuth 一键授权 | N/A（非 MCP） | 本地 stdio | 本地 stdio |
| 分层架构 | Tier1 + discover/invoke | N/A | Tier1 + discover/invoke | 全部平铺 |
| 适用场景 | 团队/企业自托管 | 命令行/脚本 | 个人/小团队 | 个人/开发调试 |

## 快速部署

### 准备工作

1. **AWS 账号** — 需要有效凭证（`aws configure`）
2. **飞书自建应用** — 在 [飞书开放平台](https://open.feishu.cn) 创建：
   - 进入 [开发者后台](https://open.feishu.cn/app) → 创建企业自建应用
   - 应用能力 → 启用**机器人**
   - 权限管理 → 开通所需 API 权限
   - 记下 **App ID** 和 **App Secret**
   - 版本管理 → 创建版本并发布

### 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)
```

脚本自动检查并安装依赖（Node.js、Docker、AWS CLI、CDK），引导输入飞书凭证并完成部署。

### 手动安装

```bash
git clone https://github.com/ddpie/lark-mcp-on-agentcore.git
cd lark-mcp-on-agentcore
./scripts/deploy.sh
```

### 部署后

脚本输出 **Redirect URL**，将它添加到飞书应用的 安全设置 → 重定向 URL。

## Quick Desktop 配置

部署完成后，按以下步骤在 Quick Desktop 中添加飞书 MCP 连接。

### 第 1 步：创建 Connector

Quick Desktop 中点击 **Settings → Capabilities → Browse connections**（跳转浏览器），选择 **Create for your team** → **Model Context Protocol**：

<p align="center">
  <img src="docs/quick-connectors-create.png" alt="Create for your team" width="600">
</p>

如果弹窗提示已有 MCP connector，点击 **No, create new**：

<p align="center">
  <img src="docs/quick-connectors-new.png" alt="No, create new" width="600">
</p>

### 第 2 步：填写连接信息

填写 Name、Description、MCP server endpoint（部署输出的 MCP Endpoint）、Connection type 选择 **Public network**，点击 **Next**：

<p align="center">
  <img src="docs/quick-mcp-connect.png" alt="Connect" width="600">
</p>

### 第 3 步：填写 OAuth 配置

填写部署输出的 Client ID、Client Secret、Token URL、Authorization URL，点击 **Create and continue**：

<p align="center">
  <img src="docs/quick-mcp-authenticate.png" alt="Authenticate" width="600">
</p>

### 第 4 步：飞书授权

浏览器自动弹出飞书授权页，点击 **Authorize**：

<p align="center">
  <img src="docs/feishu-authorize.png" alt="Feishu Authorization" width="400">
</p>

授权完成后自动跳回 Quick：

<p align="center">
  <img src="docs/quick-returning.png" alt="Returning to Quick" width="500">
</p>

### 第 5 步：发布

选择谁可以使用此连接（默认仅自己，可选 "Everyone in your organization"），点击 **Publish**：

<p align="center">
  <img src="docs/quick-mcp-publish.png" alt="Publish" width="600">
</p>

发布成功后，Connector 详情页显示所有可用工具：

<p align="center">
  <img src="docs/quick-mcp-ready.png" alt="Connector Ready" width="800">
</p>

### 第 6 步：在 Quick Desktop 中使用

回到 Quick Desktop，**Settings → Capabilities → Connections** 中搜索 feishu，点击 **Sign in**：

<p align="center">
  <img src="docs/quick-desktop-signin.png" alt="Sign in" width="600">
</p>

连接成功后即可在对话中使用飞书工具。

## 分层工具架构

参考 [lark-cli-mcp-wrapper](https://github.com/ddpie/lark-cli-mcp-wrapper) 的分层设计，LLM context 中只有 30 个工具，但实际可访问 200+ 个飞书 API：

| 层级 | 工具数 | 说明 |
|------|--------|------|
| Tier 1 | 28 | 高频工具，直接暴露给 LLM |
| `lark_discover` | 1 | 按关键词/分类搜索全部 200+ 个工具 |
| `lark_invoke` | 1 | 调用 discover 找到的任何工具 |

### Tier 1 高频工具 (28)

| 分类 | 工具 |
|------|------|
| IM | 发消息、搜索消息、群聊列表、聊天记录、搜索群 |
| 日历 | 查看日程、创建日程、查询忙闲、查找会议室 |
| 文档 | 创建文档、获取内容、搜索文档、更新文档 |
| 多维表格 | 查询表、查询记录、批量创建记录、搜索记录 |
| 云空间 | 搜索文件、上传文件、下载文件 |
| 任务 | 创建任务、查看我的任务、完成任务 |
| 通讯录 | 搜索用户、查看用户信息 |
| 表格 | 读取数据、写入数据 |
| 邮件 | 发送邮件 |

### 低频工具 (通过 lark_discover 按需搜索)

| 分类 | 示例能力 |
|------|---------|
| 多维表格 | 字段管理、视图配置、仪表盘、权限、表单、工作流 |
| 表格 | 单元格操作、条件格式、数据验证、筛选、导出 |
| 云空间 | 权限管理、评论、版本、移动/复制、分享 |
| 邮件 | 草稿、文件夹、标签、邮件规则、联系人 |
| 任务 | 子任务、清单、成员、评论、提醒、附件 |
| IM | 消息卡片、Pin、表情回复、已读回执、群公告 |
| 知识库 | 空间管理、节点操作、移动、快捷方式 |
| OKR | 目标、关键结果、对齐、进展 |
| 视频会议 | 会议记录、参会人、录制 |
| 文档 | 块操作、评论、导入导出 |
| Markdown | 创建、读取、更新、覆盖 |
| 日历 | 日历管理、订阅 |
| 妙记 | 查询、下载、AI 产物 |
| 幻灯片 | 页面管理、内容读取 |
| 画板 | 导出、编辑 |

## 架构

<p align="center">
  <img src="docs/architecture.svg" alt="Architecture" width="720">
</p>

- 所有端点在同一个 CloudFront 域名下
- 用户首次使用完成一次飞书 OAuth 授权，之后全自动
- EventBridge 每小时刷新飞书 Token，用户无感知

## 安全

| 层面 | 措施 |
|------|------|
| Token 存储 | Secrets Manager（KMS 加密，CloudTrail 审计） |
| Token 传输 | AWS 内网 TLS + SigV4，不经过公网 |
| OAuth 防 CSRF | HMAC-SHA256 签名 state（timing-safe，5 分钟过期） |
| MCP 认证 | OAuth 2.0 (PKCE + client_secret)，HMAC 签名 token（30 天有效） |
| 容器 | 无状态 per-request，非 root 运行 |
| App Secret | 存储在 Secrets Manager，运行时通过环境变量注入容器（不出现在日志或命令行） |
| 网络 | CloudFront + API Gateway，HTTPS-only |

## 成本

按需付费，无固定月费：

| 组件 | 计费方式 |
|------|---------|
| AgentCore Runtime | 按 vCPU/内存按秒计费，无请求时不收费 |
| Secrets Manager | $0.40/密钥/月 |
| Lambda / API Gateway / CloudFront | 按请求量，有免费额度 |

## 运维

```bash
./scripts/ops.sh status            # 系统概览
./scripts/ops.sh list-users        # 已授权用户
./scripts/ops.sh revoke <id>       # 撤销授权
./scripts/ops.sh rotate-secret     # 轮换 OAuth Client Secret
./scripts/ops.sh refresh-all       # 手动触发 Token 刷新
./scripts/ops.sh logs              # 查看 Lambda 日志
```

## 销毁

```bash
cd infra && npx cdk destroy --all
./scripts/ops.sh destroy           # 删除 AgentCore Runtime
```

## 项目结构

```
docker/
  Dockerfile          lark-cli ARM64 容器
  generate-tools.js   Build 时生成工具目录 (200+ tools)
  server.js           MCP server (分层: tier1 + discover/invoke)
  tier1.json          28 个高频工具
infra/
  lib/oauth-stack.ts  OAuth + MCP endpoint (CloudFront)
  lib/runtime-stack.ts  Docker 镜像 + IAM
lambda/
  token-refresh-shim/ OAuth 流程 + Token 自动刷新
  mcp-middleware/     Token 验证 + SigV4 代理
scripts/
  deploy.sh           交互式部署
  install.sh          一键安装
  ops.sh              运维工具
  test-e2e.sh         端到端测试
```

## FAQ

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

A: 重新运行 `./scripts/deploy.sh`，CDK 会重新构建 Docker 镜像并拉取最新 lark-cli。

**Q: 轮换 Client Secret 后，已有用户需要重新授权吗？**

A: 是的。`./scripts/ops.sh rotate-secret` 会使所有已发放的 MCP Token 失效，用户需在 Quick Desktop 中重新 Sign in。升级 lark-cli 版本不影响已有用户。

**Q: 支持哪些 AWS 区域？**

A: 取决于 AWS Bedrock AgentCore 的可用区域。部署脚本提供了常用区域选择。

**Q: 支持自定义域名吗？**

A: 支持。部署时脚本会提示输入自定义域名，或设置环境变量 `CUSTOM_DOMAIN=mcp.company.com`。

**Q: 支持国际版 Lark 吗？**

A: 支持。部署时设置环境变量 `LARKSUITE_CLI_BRAND=lark`。

## License

MIT

---

# English

## lark-mcp-on-agentcore

Enterprise reference architecture: Deploy 200+ Feishu/Lark APIs as a remote MCP Server on AWS Bedrock AgentCore with multi-user OAuth and per-user identity isolation.

Users connect with one click in [Amazon Quick Desktop](https://aws.amazon.com/quick/desktop/) and interact with Feishu using natural language — send messages, manage calendars, read/write Bitable, edit docs — all executed under their own Feishu identity.

### Demo

<p align="center">
  <img src="docs/quick-desktop-demo-en.png" alt="Demo">
</p>

```
> Check my Feishu calendar for today
> Send a message to the product dev group: sync requirements tomorrow at 3pm
> Review the last 3 days of group chat — what needs my follow-up?
```

### Runtime Characteristics

| Feature | Description |
|---------|-------------|
| **Stateless** | Each request is processed independently; user identity is passed via header token, no session affinity |
| **Auto-scaling** | AgentCore automatically spins up more container instances under load; scales to zero when idle |
| **Seamless upgrades** | Tool layer fully reuses lark-cli; upgrading only requires ops to run `./scripts/deploy.sh`, transparent to end users |

### Why This Project?

| | This project | [lark-cli](https://github.com/larksuite/cli) | [lark-cli-mcp-wrapper](https://github.com/ddpie/lark-cli-mcp-wrapper) | [lark-openapi-mcp](https://github.com/larksuite/lark-openapi-mcp) |
|---|---|---|---|---|
| Type | Remote MCP Server | CLI tool | Local MCP Server | Local MCP Server |
| Deployment | One command, self-hosted | npm install | npx local | npx local |
| Tool count | 200+ | 200+ (CLI) | 200+ (MCP wrapped) | 19-31 (preset limited) |
| User identity | Per-user isolation (OAuth) | Single user | Single user | Single user |
| Token mgmt | Auto acquire, refresh, encrypted storage | Local keychain | Reuses lark-cli session | User managed |
| Multi-user | 1000+ users share one deployment | N/A | N/A | N/A |
| Client conn | Remote MCP + OAuth one-click | N/A (not MCP) | Local stdio | Local stdio |
| Tiered arch | Tier1 + discover/invoke | N/A | Tier1 + discover/invoke | Flat list |
| Use case | Team / enterprise self-hosted | CLI / scripts | Individual / small team | Individual / dev |

### Quick Start

#### Prerequisites

1. **AWS account** with valid credentials (`aws configure`)
2. **Feishu custom app** — create at [Feishu Open Platform](https://open.feishu.cn):
   - [Developer Console](https://open.feishu.cn/app) → Create custom app
   - App capabilities → Enable **Bot**
   - Permissions → Grant required API scopes
   - Note the **App ID** and **App Secret**
   - Version management → Create and publish a version

#### Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)
```

The script checks/installs dependencies (Node.js, Docker, AWS CLI, CDK), prompts for Feishu credentials, and deploys.

#### Manual Install

```bash
git clone https://github.com/ddpie/lark-mcp-on-agentcore.git
cd lark-mcp-on-agentcore
./scripts/deploy.sh
```

#### Post-deployment

Add the output **Redirect URL** to your Feishu app's Security Settings → Redirect URLs.

### Architecture

<p align="center">
  <img src="docs/architecture-en.svg" alt="Architecture" width="720">
</p>

- All endpoints share a single CloudFront domain
- Users complete Feishu OAuth once on first use; fully automatic thereafter
- EventBridge refreshes Feishu tokens hourly, transparent to users

### Quick Desktop Setup

After deployment, add the Feishu MCP connection in Quick Desktop:

**Step 1: Create Connector**

Settings → Capabilities → Browse connections → Create for your team → Model Context Protocol:

<p align="center">
  <img src="docs/quick-connectors-create.png" alt="Create for your team" width="600">
</p>

If prompted about an existing MCP connector, click **No, create new**:

<p align="center">
  <img src="docs/quick-connectors-new.png" alt="No, create new" width="600">
</p>

**Step 2: Connection Info**

Fill in Name, MCP server endpoint (from deploy output), Connection type: **Public network**, click **Next**:

<p align="center">
  <img src="docs/quick-mcp-connect.png" alt="Connect" width="600">
</p>

**Step 3: OAuth Config**

Fill in Client ID, Client Secret, Token URL, Authorization URL from deploy output, click **Create and continue**:

<p align="center">
  <img src="docs/quick-mcp-authenticate.png" alt="Authenticate" width="600">
</p>

**Step 4: Feishu Authorization**

Approve in the popup Feishu authorization page:

<p align="center">
  <img src="docs/feishu-authorize.png" alt="Feishu Authorization" width="400">
</p>

After authorization, automatically returns to Quick:

<p align="center">
  <img src="docs/quick-returning.png" alt="Returning to Quick" width="500">
</p>

**Step 5: Publish**

Choose visibility (default: only you; or "Everyone in your organization"), click **Publish**:

<p align="center">
  <img src="docs/quick-mcp-publish.png" alt="Publish" width="600">
</p>

After publishing, the Connector detail page shows all available tools:

<p align="center">
  <img src="docs/quick-mcp-ready.png" alt="Connector Ready" width="800">
</p>

**Step 6: Use in Quick Desktop**

Back in Quick Desktop, **Settings → Capabilities → Connections**, search "feishu", click **Sign in**:

<p align="center">
  <img src="docs/quick-desktop-signin.png" alt="Sign in" width="600">
</p>

Once connected, Feishu tools are available in conversations.

### Tiered Tool Architecture

Only 30 tools in LLM context, but 200+ Feishu APIs accessible:

| Tier | Count | Description |
|------|-------|-------------|
| Tier 1 | 28 | High-frequency tools, directly exposed to LLM |
| `lark_discover` | 1 | Search all 200+ tools by keyword/category |
| `lark_invoke` | 1 | Call any tool found via discover |

### Security

| Layer | Measure |
|-------|---------|
| Token storage | Secrets Manager (KMS encrypted, CloudTrail audited) |
| Token transport | AWS internal TLS + SigV4, never traverses public internet |
| OAuth CSRF | HMAC-SHA256 signed state (timing-safe, 5-min expiry) |
| MCP auth | OAuth 2.0 (PKCE + client_secret), HMAC signed token (30-day validity) |
| Container | Stateless per-request, non-root |
| App Secret | Stored in Secrets Manager, injected via env var at runtime (never in logs or CLI args) |
| Network | CloudFront + API Gateway, HTTPS-only |

### Cost

Pay-as-you-go, no fixed monthly fee:

| Component | Billing |
|-----------|---------|
| AgentCore Runtime | Per vCPU/memory per second; zero cost when idle |
| Secrets Manager | $0.40/secret/month |
| Lambda / API Gateway / CloudFront | Per request, with free tier |

### Operations

```bash
./scripts/ops.sh status            # System overview
./scripts/ops.sh list-users        # Authorized users
./scripts/ops.sh revoke <id>       # Revoke authorization
./scripts/ops.sh rotate-secret     # Rotate OAuth Client Secret
./scripts/ops.sh refresh-all       # Manually trigger token refresh
./scripts/ops.sh logs              # View Lambda logs
```

### Teardown

```bash
cd infra && npx cdk destroy --all
./scripts/ops.sh destroy           # Delete AgentCore Runtime
```

### FAQ

**Q: Authentication fails when connecting from Quick Desktop?**
A: Verify the Redirect URL from deploy output is added to your Feishu app's Security Settings.

**Q: User token expired after 30 days of inactivity?**
A: Next connection automatically triggers Feishu re-authorization.

**Q: Deployment failed?**
A: The script is idempotent — just re-run. For a clean start: `cd infra && npx cdk destroy --all`.

**Q: How to restrict which users can access?**
A: Use the Feishu app's "Availability" settings. Only users in scope can complete OAuth.

**Q: How to upgrade lark-cli?**
A: Re-run `./scripts/deploy.sh`. CDK rebuilds the Docker image with the latest lark-cli. Existing users are unaffected.

**Q: Does rotating Client Secret require users to re-authorize?**
A: Yes. `./scripts/ops.sh rotate-secret` invalidates all issued MCP tokens. Users must re-sign-in via Quick Desktop. Upgrading lark-cli does not affect existing users.

**Q: Which AWS regions are supported?**
A: Depends on AWS Bedrock AgentCore availability. The deploy script offers common region choices.

**Q: Custom domain support?**
A: Yes. Set `CUSTOM_DOMAIN=mcp.company.com` or follow the deploy script prompt.

**Q: Lark (international) support?**
A: Yes. Set `LARKSUITE_CLI_BRAND=lark` during deployment.

### Project Structure

```
docker/
  Dockerfile          lark-cli ARM64 container
  generate-tools.js   Build-time tool catalog generation (200+ tools)
  server.js           MCP server (tiered: tier1 + discover/invoke)
  tier1.json          28 high-frequency tools
infra/
  lib/oauth-stack.ts  OAuth + MCP endpoint (CloudFront)
  lib/runtime-stack.ts  Docker image + IAM
lambda/
  token-refresh-shim/ OAuth flow + automatic token refresh
  mcp-middleware/     Token verification + SigV4 proxy
scripts/
  deploy.sh           Interactive deployment
  install.sh          One-click install
  ops.sh              Operations toolkit
  test-e2e.sh         End-to-end tests
```

### License

MIT
