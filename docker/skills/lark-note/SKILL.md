---
name: lark-note
description: "飞书会议纪要（Note）直查：已知 note_id 时查询纪要详情、展示类型、关联文档 token，并读取 unified 原始逐字记录。当用户已持有 note_id，或从文档显式 vc-node-id 获得 note_id 时使用。不负责会议/日程/妙记定位、文档标题搜索或 Docx 正文读取。高频操作优先使用 lark_note_detail、lark_note_transcript。"
---

# note (v1)

（认证由 MCP server 自动处理，始终以 user 身份执行。）

Note 域只接受显式 `note_id`：用户直接提供，或 `lark_docs_fetch(api_version="v2")` 返回的 `<vc-transcribe-tab vc-node-id="...">` 中的 `vc-node-id`。不要从 `doc_token`、标题、正文或 backlink 反推 `note_id`。

## 命令路由

| 用户表达 / 上下文 | 路由 |
|---------|------|
| 已知 `note_id`，查纪要类型 / 文档 token | `lark_note_detail(note_id="NOTE_ID")` |
| `lark_docs_fetch(api_version="v2")` 返回 `<vc-transcribe-tab vc-node-id="...">` | 取 `vc-node-id` 作为 `NOTE_ID`，先 `lark_note_detail(note_id="NOTE_ID")` |
| 已知 `note_id`，读纪要正文 | `lark_note_detail` → `lark_docs_fetch(api_version="v2", doc="<note_doc_token>")` |
| 已知 `note_id`，查 unified 原始记录 / 逐字稿 | `lark_note_transcript(note_id="NOTE_ID")` |
| 只有自然语言纪要标题，用户要逐字稿 / 原始记录 / 谁说了什么 | 不进本 skill；先走文档搜索与 `lark_docs_fetch`，拿到 `vc-node-id` 后再回来 |

## `note_display_type` 路由

| `lark_note_detail` 结果 | 用户要逐字稿 / 原始记录时 |
|------|---------------|
| `normal` + `verbatim_doc_token` 非空 | `lark_docs_fetch(api_version="v2", doc="<verbatim_doc_token>")` |
| `unknown` + `verbatim_doc_token` 非空 | 先按独立文档处理；不要猜成 unified |
| `unknown` + 无逐字稿 token | 停止重试并说明无法确定逐字稿入口 |
| `unified` | `lark_note_transcript(note_id="<note_id>")` |

判别键是 `note_display_type`，不是 `verbatim_doc_token` 是否为空：unified 纪要也可能返回非空 `verbatim_doc_token`。

## 关键字段

- `note_id`：Note 域唯一入口。
- `note_display_type`：`unknown` / `normal` / `unified`。
- `note_doc_token`：纪要正文文档，正文读取交给 `lark_get_skill(domain="doc")`。
- `verbatim_doc_token`：普通纪要逐字稿文档；unified 逐字稿不按这个 token 路由。

## 不在本 Skill 范围

- 通过 `meeting_id` / `calendar_event_id` / `minute_token` 定位纪要 → `lark_get_skill(domain="vc")`。
- 自然语言纪要标题搜索 → `lark_get_skill(domain="drive")` / `lark_get_skill(domain="doc")`。
- Docx 正文读取 → `lark_get_skill(domain="doc")`。
- 妙记基础信息与媒体文件 → `lark_get_skill(domain="minutes")`。

## Shortcuts

| Shortcut | 何时读 reference |
|----------|------|
| `lark_note_detail` | 需要解释输出字段或根据展示类型继续路由，先调用 `lark_get_skill(domain="note", section="detail")` |
| `lark_note_transcript` | 需要拉取 unified 原始记录或处理本地输出文件，先调用 `lark_get_skill(domain="note", section="transcript")` |
