
# vc +notes

查询会议纪要，支持通过会议 ID、妙记 Token 或日程事件 ID 获取纪要文档、逐字稿、AI 总结、待办和章节。只读操作。

（authentication is handled automatically by the MCP server）

## 命令

```
# 通过会议 ID 查询（逗号分隔支持批量，最多 50 个）
lark_vc_notes(meeting_ids="69xxxxxxxxxxxxx28")
lark_vc_notes(meeting_ids="69xxxxxxxxxxxxx28,69xxxxxxxxxxxxx29")

# 通过妙记 Token 查询（从妙记 URL 中提取）
lark_vc_notes(minute_tokens="obbxxxxxxxxxxxxxxxxxx")
lark_vc_notes(minute_tokens="obbxxxxxxxxxxxxxxxxxx,obbyyyyyyyyyyyyyyyyyy")

# 指定逐字稿输出目录（仅 minute_tokens 路径有效）
lark_vc_notes(minute_tokens="obbxxxxxxxxxxxxxxxxxx", output_dir="./output")
lark_vc_notes(minute_tokens="obbxxxxxxxxxxxxxxxxxx", overwrite=true)

# 通过日程事件 ID 查询（从 lark_calendar_agenda 获取 event_id）
lark_vc_notes(calendar_event_ids="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx_0")

# 输出格式
lark_vc_notes(meeting_ids="69xxxxxxxxxxxxx28", format="json")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `meeting_ids` | 三选一 | 会议 ID，逗号分隔支持批量 |
| `minute_tokens` | 三选一 | 妙记 Token，逗号分隔支持批量 |
| `calendar_event_ids` | 三选一 | 日程事件 ID，逗号分隔支持批量 |
| `output_dir` | 否 | 逐字稿输出目录。未指定时默认落到 `./minutes/{minute_token}/transcript.txt`（与 `lark_minutes_download` 共享目录）；显式指定时沿用旧布局 `./{output_dir}/artifact-{title}-{token}/transcript.txt`。仅 `minute_tokens` 路径有效 |
| `overwrite` | 否 | 覆盖已存在的逐字稿文件，仅 `minute_tokens` 路径有效 |

## 核心约束

### 1. 三种参数互斥

每次只能指定一种输入方式。同时传入多种会报错。

### 2. 仅支持 user 身份

该工具仅支持 user 身份（authentication is handled automatically by the MCP server）。

### 3. 批量上限

每次最多传入 50 个 ID/Token。

### 4. 按路径检查权限

不同输入方式需要不同权限，工具会自动检查对应路径所需的 scope：

| 输入 | 所需权限 |
|------|---------|
| `meeting_ids` | `vc:meeting.meetingevent:read`、`vc:note:read` |
| `minute_tokens` | `vc:note:read`、`minutes:minutes:readonly`、`minutes:minutes.artifacts:read`、`minutes:minutes.transcript:export` |
| `calendar_event_ids` | `calendar:calendar:read`、`calendar:calendar.event:read`、`vc:meeting.meetingevent:read`、`vc:note:read` |

## 输出结果

### 有纪要文档时

返回 `notes` 数组，每条记录包含：

| 字段 | 说明 |
|------|------|
| `note_doc_token` | **AI 智能纪要**文档 Token — AI 生成的总结、待办、章节 |
| `meeting_notes` | **用户绑定的会议纪要**文档 Token 列表 — 用户主动关联到会议的文档（仅 `calendar_event_ids` 路径返回） |
| `verbatim_doc_token` | **逐字稿**文档 Token — 完整的逐句文字记录，含说话人和时间戳 |
| `shared_doc_tokens` | 会中共享文档 Token 列表 |
| `creator_id` | 创建者 ID |
| `create_time` | 创建时间（格式化） |

> **选择哪个 token？** 用户说"会议纪要""总结""待办""纪要内容" → 返回 `note_doc_token` 和 `meeting_notes`（如有）。用户说"逐字稿""完整记录""谁说了什么" → 用 `verbatim_doc_token`。意图不明确时，展示所有文档链接让用户选择。

### minute_tokens 路径的 AI 产物

通过 `minute_tokens` 查询时，返回的 `artifacts` 字段包含 AI 内置产物：

| 字段 | 说明 |
|------|------|
| `artifacts.summary` | AI 总结（JSON 内联） |
| `artifacts.todos` | 待办事项（JSON 内联） |
| `artifacts.chapters` | 章节纪要（JSON 内联） |
| `artifacts.keywords` | 妙记推荐关键词（JSON 内联） |
| `artifacts.transcript_file` | 逐字稿本地文件路径。默认落到 `./minutes/{minute_token}/transcript.txt`（与 `lark_minutes_download` 聚合）；显式 `output_dir` 时走旧布局 `./{output_dir}/artifact-{title}-{token}/transcript.txt` |

## 如何获取输入参数

| 输入参数 | 获取方式 |
|---------|---------|
| `meeting_id` | `lark_vc_search` 搜索历史会议 → 结果中的 `id` 字段 |
| `minute_token` | 从妙记 URL 中提取，如 `https://sample.feishu.cn/minutes/obbyyyyyyyyyyyyyyyyyy` → `obbyyyyyyyyyyyyyyyyyy` |
| `calendar_event_id` | `lark_calendar_agenda` 查看日程 → 结果中的 `event_id` 字段 |

## 常见错误与排查

| 错误现象 | 根本原因 | 解决方案 |
|---------|---------|---------|
| `exactly one of ... is required` | 未传入参数或同时传了多种 | 只指定一种输入方式 |
| `no notes available for this meeting` | 该会议未生成纪要 | 尝试用 `minute_tokens` 路径 |
| `121005 no permission` | 非会议参与者无权查看 | 使用 `minute_tokens` 降级到内置产物 |
| `missing required scope(s)` | 权限不足 | 联系管理员授权对应 scope |
| `too many IDs` | 超过批量上限 | 分批查询，每批最多 50 个 |

## 提示
- 默认使用 `format="json"` 输出，你更擅长解析 JSON 数据。
- `meeting_ids` 和 `calendar_event_ids` 路径最终都走纪要详情 API，需要 `vc:note:read` 权限。
- `minute_tokens` 路径无纪要权限时会自动降级，**不会报错**，而是下载内置产物到本地。

## 参考

- lark_get_skill(domain="vc") — 视频会议全部命令
- lark_get_skill(domain="vc", section="search") — 搜索历史会议（获取 meeting_id）
