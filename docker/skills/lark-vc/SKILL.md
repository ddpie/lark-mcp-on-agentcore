# vc (v1)

## 核心概念

- **视频会议（Meeting）**：飞书视频会议实例，通过 meeting\_id 标识。已结束的会议支持通过关键词、时间段、参会人、组织者、会议室等条件搜索（见 `lark_vc_search`）。
- **会议纪要（Note）**：视频会议结束后生成的结构化文档，包含纪要文档（包含总结、待办、章节）和逐字稿文档。
- **妙记（Minutes）**：来源于飞书视频会议的录制产物或用户上传的音视频文件，支持视频/音频的转写和会议纪要，通过 minute\_token 标识。
- **纪要文档（MainDoc）**：AI 智能纪要的主文档，包含 AI 生成的总结和待办，对应 `note_doc_token`。
- **用户会议纪要（MeetingNotes）**：用户主动绑定到会议的纪要文档，对应 `meeting_notes`。仅通过 `calendar_event_ids` 路径返回。
- **逐字稿（VerbatimDoc）**：会议的逐句文字记录，包含说话人和时间戳。

## 核心场景

### 1. 搜索会议记录
1. 仅支持搜索已结束的会议，对于还未开始的未来会议，需要使用 lark-calendar 技能。
2. 仅支持使用关键词、时间段、参会人、组织者、会议室等筛选条件搜索会议记录，对于不支持的筛选条件，需要提示用户。
3. 搜索结果存在多条数据时，务必注意分页数据获取，不要遗漏任何会议记录。

### 2. 整理会议纪要
1. 整理纪要文档时默认给出纪要文档和逐字稿链接即可，无需读取纪要文档或逐字稿内容。
2. 用户明确需要获取纪要文档中的总结、待办、章节产物时，再读取文档获取具体内容。
3. 读取智能纪要（`note_doc_token`）内容时，纪要文档的**第一个 `<whiteboard>`** 标签是封面图（AI 生成的总结可视化），应同时下载展示给用户：
```
# 1. 读取纪要内容
lark_docs_fetch(api_version="v2", doc="<note_doc_token>", doc_format="markdown")
# 2. 从返回的 markdown 中提取第一个 <whiteboard token="xxx"/> 的 token
# 3. 下载封面图到聚合目录（和逐字稿、录像同目录，保持产物归拢）
#    并非所有纪要都有封面画板，没有 <whiteboard> 标签时跳过即可
lark_docs_media_download(type="whiteboard", token="<whiteboard_token>", output="./minutes/<minute_token>/cover")
```
> **产物目录规范**：同一会议的所有下载产物（录像、逐字稿、封面图等）统一放到 `./minutes/{minute_token}/` 目录下。这与 `lark_minutes_download` 和 `lark_vc_notes(minute_tokens=...)` 的默认落点保持一致，便于 Agent 聚合。显式路径（如封面图）需手动对齐到同一目录。

> **纪要相关文档 — 根据用户意图选择：**
> - `note_doc_token` → **AI 智能纪要**（AI 总结 + 待办 + 章节）
> - `meeting_notes` → **用户绑定的会议纪要**（用户主动关联到会议的文档，仅 `calendar_event_ids` 路径返回）
> - `verbatim_doc_token` → **逐字稿**（完整的逐句文字记录，含说话人和时间戳）— 用户说"逐字稿""完整记录""谁说了什么"时用这个
> - 用户说"纪要""总结""纪要内容"时，应同时返回 `note_doc_token` 和 `meeting_notes`（如有）
> - 用户意图不明确时，应展示所有文档链接让用户选择，而不是替用户决定
> - 如果用户提供的是**本地音视频文件**并说"转纪要""转逐字稿"，不要直接从 `lark_vc_notes` 开始；应先用 lark-minutes 的上传流程生成 `minute_url`，再提取 `minute_token` 调用 `lark_vc_notes(minute_tokens="<minute_token>")`

### 3. 纪要文档与逐字稿链接
1. 纪要文档、逐字稿文档与关联的共享文档默认使用文档 Token 返回。
2. 仅需要获取文档名称和 URL 等基本信息时，使用 `lark_invoke` 查询：
```
# 查看命令使用方式
lark_discover(query="drive.metas.batch_query")

# 批量获取文档基本信息: 一次最多查询 10 个文档
lark_invoke(tool_name="lark_drive_metas_batch_query", args={
  data: {"request_docs": [{"doc_type": "docx", "doc_token": "<doc_token>"}], "with_url": true}
})
```
3. 需要获取文档内容时，使用 `lark_docs_fetch`：
```
# 获取文档内容
lark_docs_fetch(api_version="v2", doc="<doc_token>", doc_format="markdown")
```

### 4. 查询参会人快照（读操作）

用户问"谁参加过这场会议""这个会议有哪些参会人""某某参会了吗"等**参会人快照**类问题时，使用 **`lark_invoke` 调用 vc meeting get**：这是参会人服务端快照 API，不依赖 bot 身份参会，**已结束会议也可查**：

```
lark_invoke(tool_name="lark_vc_meeting_get", args={
  params: {"meeting_id": "<meeting_id>", "with_participants": true}
})
```

选型判断表：

| 用户意图 | 推荐工具 | 所在 skill |
|---------|---------|--------|
| 参会人快照（谁参加过、何时入/离会，任意时点）| `lark_invoke(tool_name="lark_vc_meeting_get", args={params: {"meeting_id":"...", "with_participants": true}})` | 本 skill |
| 已结束会议的发言内容 | `lark_vc_notes` 取 `verbatim_doc_token` 再 `lark_docs_fetch(api_version="v2")` | 本 skill |
| **进行中会议**的实时事件流（转写、聊天、共享、会中加入/离开）| `lark_vc_meeting_events` | lark-vc-agent |
| **Agent 真实入会 / 离会** | `lark_vc_meeting_join` / `lark_vc_meeting_leave` | lark-vc-agent |

## 资源关系

```
Meeting (视频会议)
├── Note (会议纪要)
│   ├── MainDoc (AI 智能纪要文档, note_doc_token)
│   ├── MeetingNotes (用户绑定的会议纪要文档, meeting_notes)
│   ├── VerbatimDoc (逐字稿, verbatim_doc_token)
│   └── SharedDoc (会中共享文档)
└── Minutes (妙记) ← minute_token 标识，lark_vc_recording 从 meeting_id 获取
    ├── Transcript (文字记录)
    ├── Summary (总结)
    ├── Todos (待办)
    ├── Chapters (章节)
    └── Keywords (推荐关键词)
```

> **注意**：`lark_vc_search` 只能查询已结束的历史会议。查询未来的日程安排请使用 lark-calendar。
>
> **优先级**：当用户搜索历史会议时，应优先使用 `lark_vc_search` 而非 `lark_calendar_events_search`。calendar 的搜索面向日程，vc 的搜索面向已结束的会议记录，支持按参会人、组织者、会议室等维度过滤。
>
> **路由规则**：如果用户在问"开过的会""今天开了哪些会""最近参加过什么会""已结束的会议""历史会议记录"，优先使用 `lark_vc_search`。只有在查询未来日程、待开的会、agenda 时才优先使用 lark-calendar。
>
> **妙记边界**：`lark_vc_notes` 负责纪要内容、逐字稿和 AI 产物；妙记基础信息请优先看 `lark_vc_recording` 与 lark-minutes。
>
> **文件转纪要边界**：如果用户给的是本地音视频文件，并希望得到纪要、逐字稿、总结、待办或章节，入口应先走 lark-minutes 的上传流程生成 `minute_url` / `minute_token`，再回到 `lark_vc_notes(minute_tokens="<minute_token>")` 获取内容产物。
>
> **特殊情况**: 当用户查询"今天有哪些会议"时，通过 `lark_vc_search` 查询今天开过的会议记录，同时使用 lark-calendar 技能查询今天还未开始的会议，统一整理后展示给用户。

## Shortcuts（推荐优先使用）

Shortcut 是对常用操作的高级封装。有 Shortcut 的操作优先使用。

| Shortcut | 说明 |
|----------|------|
| `lark_vc_search` | Search meeting records (requires at least one filter) |
| `lark_vc_notes` | Query meeting notes (via meeting-ids, minute-tokens, or calendar-event-ids) |
| `lark_vc_recording` | Query minute_token from meeting-ids or calendar-event-ids |

- 使用 `lark_vc_search` 时，必须先调用 lark_get_skill(domain="vc", section="search")，了解搜索参数和返回值结构。
- 使用 `lark_vc_notes` 时，必须先调用 lark_get_skill(domain="vc", section="notes")，了解查询参数、产物类型和返回值结构。
- 使用 `lark_vc_recording` 时，必须先调用 lark_get_skill(domain="vc", section="recording")，了解查询参数和返回值结构。

> **Agent 参会相关命令已独立**：`lark_vc_meeting_join` / `lark_vc_meeting_leave` / `lark_vc_meeting_events` 请使用 lark-vc-agent 技能。

## API Resources

```
lark_discover(query="vc.<resource>.<method>")   # 调用 API 前必须先查看参数结构
lark_invoke(tool_name="lark_vc_<resource>_<method>", args={...})  # 调用 API
```

> **重要**：使用原生 API 时，必须先运行 `lark_discover` 查看 `params` / `data` 参数结构，不要猜测字段格式。

### meeting

  - `get` — 获取会议详情（主题、时间、参会人、note_id）

```
# 获取会议基础信息：不包含参会人列表
lark_invoke(tool_name="lark_vc_meeting_get", args={
  params: {"meeting_id": "<meeting_id>"}
})

# 获取会议基础信息：包含参会人列表
lark_invoke(tool_name="lark_vc_meeting_get", args={
  params: {"meeting_id": "<meeting_id>", "with_participants": true}
})
```

### minutes（跨域，详见 lark-minutes）

  - `get` — 获取妙记基础信息（标题、时长、封面）；查询纪要**内容**请用 `lark_vc_notes(minute_tokens="<minute_token>")`

## 权限表

| 方法 | 所需 scope |
|------|-----------|
| `lark_vc_notes(meeting_ids=...)` | `vc:meeting.meetingevent:read`、`vc:note:read` |
| `lark_vc_notes(minute_tokens=...)` | `vc:note:read`、`minutes:minutes:readonly`、`minutes:minutes.artifacts:read`、`minutes:minutes.transcript:export` |
| `lark_vc_notes(calendar_event_ids=...)` | `calendar:calendar:read`、`calendar:calendar.event:read`、`vc:meeting.meetingevent:read`、`vc:note:read` |
| `lark_vc_recording(meeting_ids=...)` | `vc:record:readonly` |
| `lark_vc_recording(calendar_event_ids=...)` | `vc:record:readonly`、`calendar:calendar:read`、`calendar:calendar.event:read` |
| `lark_vc_search` | `vc:meeting.search:read` |
| `lark_vc_meeting_get` | `vc:meeting.meetingevent:read` |

> Agent 参会相关 scope（`vc:meeting.bot.join:write` / `vc:meeting.meetingevent:read`）见 lark-vc-agent 技能。
