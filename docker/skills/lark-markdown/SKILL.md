---
name: lark-markdown
description: "飞书 Markdown：查看、创建、上传、编辑和比较 Markdown 文件。当用户需要创建或编辑 Markdown 文件、读取、修改、局部 patch 或比较差异时使用。"
---

# markdown (v1)

## 快速决策

- 用户要**上传、创建一个原生 `.md` 文件**，使用 `lark_markdown_create`
- 用户要**比较原生 `.md` 文件的历史版本差异**，或比较远端 Markdown 与本地草稿，使用 `lark_markdown_diff`
- 用户要**读取 Drive 里某个 `.md` 文件内容**，使用 `lark_markdown_fetch`
- 用户要对 Markdown 文件做**局部文本替换 / 正则替换**，优先使用 `lark_markdown_patch`
- 用户要**覆盖更新 Drive 里某个 `.md` 文件内容**，使用 `lark_markdown_overwrite`
- 用户要先拿 Markdown 文件的历史版本号，再做比较/下载/回滚，先用 `lark_get_skill(domain="drive")` 查看 `drive +version-history`
- 用户要把本地 Markdown **导入成在线新版文档（docx）**，不要用本 skill，改用 `lark_get_skill(domain="drive")` 查看 `drive +import --type docx`
- 用户要对 Markdown 文件做**rename / move / delete / 搜索 / 权限 / 评论**等云空间（云盘/云存储）操作，不要留在本 skill，切到 `lark_get_skill(domain="drive")`

## 核心边界

- 本 skill 处理的是 **Drive 中作为普通文件存储的 Markdown**，不是 docx 文档
- `name` 和本地 `file` 文件名都必须显式带 `.md` 后缀；不满足时工具会直接报错
- `content` 支持：
  - 直接传字符串
  - `@file` 从本地文件读取内容
  - `-` 从 stdin 读取内容
- `lark_markdown_patch` 的内部语义是：**先完整下载 Markdown，再本地替换，再整文件覆盖上传**
- `lark_markdown_patch` 不是服务端原子 patch；它是服务端编排出来的局部更新能力
- `lark_markdown_patch` 当前只支持**单组** `pattern` / `content`
- `lark_markdown_patch` 替换后的最终内容**不能为空**；如果替换后整篇 Markdown 变成空字符串，工具会直接报错，不会上传空文件
- `file` 只接受本地 `.md` 文件路径

## Shortcuts（推荐优先使用）

| Shortcut | 说明 |
|----------|------|
| `lark_get_skill(domain="markdown", section="create")` | Create a Markdown file in Drive |
| `lark_get_skill(domain="markdown", section="diff")` | Compare two remote Markdown versions, or compare remote Markdown against a local file |
| `lark_get_skill(domain="markdown", section="fetch")` | Fetch a Markdown file from Drive |
| `lark_get_skill(domain="markdown", section="patch")` | Patch a Markdown file in Drive via fetch-local-replace-overwrite |
| `lark_get_skill(domain="markdown", section="overwrite")` | Overwrite an existing Markdown file in Drive |

## 参考

- `lark_get_skill(domain="drive")` — Drive 文件管理、导入 docx、move/delete/search 等
