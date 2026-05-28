# apps (v1)

```
# 常用示例
lark_apps_create(name="客户调研问卷", app_type="HTML")
lark_apps_html_publish(app_id="app_xxx", path="./dist")
lark_apps_access_scope_set(app_id="app_xxx", scope="tenant")
```

## 写 HTML 前的硬约束（避免 publish 阶段被拒）

- **入口文件必须叫 `index.html`** — 妙搭以 `index.html` 作为应用入口；目录形态时根目录下要有 `index.html`，单文件形态时文件名就是 `index.html`。命名成 `app.html` / `demo.html` 等会被 `lark_apps_html_publish` 直接拒绝
- **`path` 内不能含已知凭据文件** — Validate 阶段会扫描 `.env` / `.env.*` / `.npmrc` / `.netrc` / `.git-credentials` / `.aws/credentials` / `.docker/config.json` / `.kube/config`，命中就拒绝。要么从产物目录里清掉这些文件，要么明确传 `allow_sensitive=true` 跳过这道检查

## 端到端流程（HTML / PPT / 静态网站发布）

**第一步：判断用户意图是「明示部署」还是「仅演示」**：

| 用户表达 | 意图 | 处理 |
|---------|------|------|
| "部署 ./xxx 的 HTML"、"发布到妙搭"、"开发 xxx 并部署成可分享的网站 / 可访问的链接"、"生成可分享 URL" | **明示部署 / 分享** | 不停下追问，HTML 写完直接走下表 step 1→2 |
| "用 HTML 写一个 PPT / 幻灯片 / 演示文稿"、"做个可演示的 demo"、"写个介绍 xxx 的页面"（没提部署 / 分享 / URL） | **仅演示** | HTML 写完先输出本地文件路径 + 简要说明，**主动追问一句**："要部署到妙搭以便分享给别人吗？"用户同意再走 step 1→2；用户说不用就停 |

**第二步：用户同意部署 / 已明示部署后，按下表走完整链路并把最终 URL 返回给用户**：

| 步骤 | 工具调用 | 说明 |
|------|------|------|
| 1. 新建应用 | `lark_apps_create(name="<根据内容主题起的应用名>", app_type="HTML")` → 从响应里拿 `app_id` | 默认都走新建（**不要尝试搜索 / 枚举已有应用**）。用户明确要复用现有应用时让他提供 **妙搭应用链接** 或 **app_id 字符串** |
| 2. 发布 HTML | `lark_apps_html_publish(app_id="<id>", path="<文件或目录>")` | 必走 |
| 3. 设置可用范围（可选） | `lark_apps_access_scope_set(app_id="<id>", scope="tenant")` 等 | 用户说"公开 / 全员可见 / 让 Alice 看 / 互联网可分享"等 |

报告给用户的话术：

> 应用「{name}」已发布，访问链接：`{url}`

若用户没指定可用范围且场景明显需要分享，主动追问一句"要设为企业全员 / 互联网公开吗？"，但不要为了问而问。

## 快速决策

- 用户**明示**"部署 / 发布 ./xxx 的 HTML"、"开发 xxx 并部署成可分享的网站 / 可访问的链接"、"发到妙搭" → 直接走「端到端流程」step 1→2，`lark_apps_html_publish` 自动部署并返回 URL，不要追问
- 用户**只说**"用 HTML 写 PPT / 幻灯片 / 演示文稿 / demo"、"开发一个可演示的页面"（**没提**部署 / 分享 / URL） → HTML 写完先输出本地路径 + 简要说明，主动问一句"要部署到妙搭以便分享吗？"，用户同意才走 publish；不要擅自部署，但也不要忘了问
- 用户说"把应用 X 开放给全员 / 全公司" → `scope="tenant"`，不要再传别的 flag
- 用户说"公开 / 让任何人都能访问 / 互联网可见" → `scope="public", require_login=<bool>`，二选一
- 用户说"只让 Alice / 某部门 / 某群访问" → `scope="specific", targets='<JSON>'`；姓名先用 `lark_get_skill(domain="contact")` 换 `ou_id`，群名先用 `lark_get_skill(domain="im")` 换 `chat_id`
- 用户没给 app_id → **默认 `lark_apps_create(name="<根据内容主题起的名字>", app_type="HTML")` 新建一个**。**不要尝试搜索 / 枚举已有应用**。如果用户明确要复用现有应用，**让他提供下列任一种**：
  - **妙搭应用链接**：形如 `https://miaoda.feishu.cn/app/app_xxxxxxxxxxxxx`（或带尾斜杠 `/app/app_xxx/`）—— `app_id` 是 `/app/` 后面的 path segment（以 `app_` 开头）
  - **app_id 字符串**：用户直接给的 `app_xxxxxxxxxxxxx`，不需要再做处理
- `path` 既可传单个 HTML 文件也可传目录；目录会**递归打包成 tar.gz 不做过滤**，要提醒用户传干净的产物目录（如 `./dist`），避免把 `.git` / `node_modules` 一起打进去
- `lark_apps_update` 只更新传入字段，未传字段保持不变；`name` / `description` 至少传一个，否则 Validate 阶段直接拦截
- `lark_apps_access_scope_set` 三种 scope **互斥**：specific 必传 `targets`、不允许 `require_login`；public 必传 `require_login`、不允许 `targets` / `apply_enabled` / `approver`；tenant 不允许任何其他 flag
- 失败时**优先转述 `error.hint`**（可执行修复建议），hint 为空时退回 `error.message`；不要原样把 envelope JSON 复述给用户

## Shortcuts（推荐优先使用）

| Shortcut | 说明 |
|----------|------|
| `lark_get_skill(domain="apps", section="create")` | 创建妙搭应用（name / description / icon-url） |
| `lark_get_skill(domain="apps", section="update")` | 部分更新应用名 / 描述（只发传入字段） |
| `lark_get_skill(domain="apps", section="access-scope-set")` | 设置应用可用范围（specific / public / tenant，三态互斥校验） |
| `lark_get_skill(domain="apps", section="access-scope-get")` | 查看应用当前可用范围（响应 scope 枚举 `All` / `Tenant` / `Range`） |
| `lark_get_skill(domain="apps", section="html-publish")` | **把本地 HTML 文件 / 目录 / PPT / 静态网站部署为可分享的妙搭应用，返回访问 URL** |
