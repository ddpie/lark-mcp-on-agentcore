
# lark_vc_meeting_events

(authentication is handled automatically by the MCP server)

查询当前 bot 在一场正在进行的视频会议中收到的会中事件列表。该工具是**读操作**。对进行中会议，要求 bot 当前仍在会中；对已结束会议，存在一个**结束后 5 分钟内的宽限窗口**，只要 bot 曾经在这场会里出现过，仍可继续拉取事件。

本工具对应 shortcut：`lark_vc_meeting_events`（调用 `GET /open-apis/vc/v1/bots/events`）。

## 调用方式

```
# 默认用法：全量拉取当前可见事件
lark_vc_meeting_events(meeting_id="69xxxxxxxxxxxxx28", page_all=true, format="pretty")

# 指定时间范围，并拉全该时间窗内当前可见事件
lark_vc_meeting_events(meeting_id="69xxxxxxxxxxxxx28", start="2026-04-17T15:00:00+08:00", end="2026-04-17T16:00:00+08:00", page_all=true, format="pretty")

# 基于上一次保存的 page_token 继续查新增事件
lark_vc_meeting_events(meeting_id="69xxxxxxxxxxxxx28", page_token="<last_page_token>", page_all=true, format="pretty")

# 调试或控制返回体大小时，显式只查一页
lark_vc_meeting_events(meeting_id="69xxxxxxxxxxxxx28", page_size="20", format="json")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `meeting_id` | 是 | 会议 ID（长数字 ID，不是 9 位会议号） |
| `start` | 否 | 起始时间，支持 ISO 8601 / `YYYY-MM-DD` / Unix 秒 |
| `end` | 否 | 结束时间，支持 ISO 8601 / `YYYY-MM-DD` / Unix 秒 |
| `page_token` | 否 | 从指定分页游标继续拉取下一页 |
| `page_size` | 否 | 单页模式每页大小。工具会自动夹紧到 `20-100`；传 `page_all=true` 时固定使用 `100` |
| `page_all` | 否 | 自动分页，直到没有更多页面为止（内部有安全上限） |
| `format` | 否 | 输出格式：json (默认) / pretty（本 skill 推荐默认） / table / ndjson / csv |

## 核心约束

### 1. 输入必须是 meeting_id，不是 9 位会议号

`meeting_id` 必须是会议的长数字 ID。它通常来自：
- `lark_vc_meeting_join` 返回体中的 `meeting.id`
- `lark_vc_search` 结果中的 `id`

**不要**把 9 位会议号（`meeting_number`）传给这个工具。

### 2. 仅支持 user 身份

该工具仅支持 `user` 身份。

### 3. bot 必须在会中，或在会议结束后的 5 分钟宽限窗口内曾经在会中

这是查询"bot 在会中观察到的事件"的接口。若 bot 已离会、未入会、或会议已经无法再判断 bot 身份，后端通常会报：
- `bot is not in meeting, no permission`

因此，最稳妥的调用顺序通常是：

```
# 先入会
lark_vc_meeting_join(meeting_number="123456789")

# 记录返回的 meeting.id

# 再查询事件
lark_vc_meeting_events(meeting_id="<meeting.id>")
```

更精确地说，后端当前的判断规则是：

- **会议进行中**：要求 bot **当前仍在会中**
- **会议已结束后的 5 分钟内**：只要 bot **曾经在这场会中出现过**，仍可拉取事件
- **会议结束超过 5 分钟**：按会议结束处理，通常不再返回事件流
- **bot 从未真实入会过**：即使会议仍在进行或刚结束，也会返回 `10005 bot is not in meeting`

### 4. 自动分页规则

- **先分清两层默认值**：
  - shortcut 本身：不传 `page_all` 时，只查 1 页。
  - 本 skill 的默认策略：除非用户明确要求只看一页，或你确实需要控制返回体大小，否则默认**必须主动带 `page_all=true`**，把当前可见事件尽量一次拉全。
- 传 `page_all=true`：开启自动分页，直到没有更多页面为止。
- `page_all=true` 时，工具固定使用最大 `page_size=100`。

执行准则：

- **默认调用模板**：`lark_vc_meeting_events(meeting_id="<meeting.id>", page_all=true, format="pretty")`
- 如果你发现自己执行成了不带 `page_all` 的单页查询，而响应里又出现 `has_more=true` / `more available` / 非空 `page_token`，应立刻意识到这只是部分结果。
- 遇到上述情况，默认补救方式是继续使用返回的 `page_token` 续拉，例如：`lark_vc_meeting_events(meeting_id="<meeting.id>", page_token="<returned_page_token>", page_all=true, format="pretty")`
- 只有在用户明确要求"就看第一页""先不要翻页"时，才不要默认带 `page_all=true`
- 只要你是基于 `lark_vc_meeting_events` 来回答一场**正在进行中的会议内容**，就不能直接复用上一次查询结果。无论用户是在问"现在是谁在说话""刚刚发生了什么""最新事件有哪些"，还是让你"总结一下这个会议讲什么"，都必须先重新执行一次 `lark_vc_meeting_events`，确认拿到的是最新事件流，再回答用户。只有在用户明确要求基于某次历史快照继续分析时，才可以复用旧结果。

### 5. pretty / json 输出差异

- `format="pretty"`：输出会议主题、会议时间和逐条时间线，适合快速理解"发生了什么"，也是本 skill 的默认推荐格式。
- `format="json"`：保留完整原始 `events[]` 结构——参会人 open_id、聊天原文、share_doc、分页字段都在原始响应里，适合提取字段、联动其他工具或做进一步程序处理。

**选型原则**：只要目标是告诉用户"发生了什么"，默认就用 `page_all=true, format="pretty"`；只有在需要完整原始消息流和结构化字段时，才改用 `json`。

> **注意**：pretty 输出中的正文文本会做单行转义，真实换行会显示为 `\n`，避免打乱时间线布局。

### 6. 内容理解模式：共享文档不能只看标题

当用户意图是：

- "总结这个会议"
- "这个会议讲了什么"
- "有哪些结论 / 待办 / 关键讨论"
- "共享文档里在讲什么"

不要只基于事件时间线直接回答。此时 `lark_vc_meeting_events` 只是**线索发现器**，不是最终信息源。

执行准则：

- 这类问题默认先用 `lark_vc_meeting_events(meeting_id="<meeting.id>", page_all=true, format="json")` 拉取最新事件流。
- 如果事件中出现共享文档线索，例如：
  - `magic_share_started`
  - `share_doc.title`
  - `share_doc.url`
- 必须继续读取共享文档内容，再生成总结，不能只根据"开始共享了某文档"这条事件和文档标题来概括会议内容。
- 若存在多个共享文档，优先读取**最近一次共享**的文档。
- 若文档读取失败，必须明确说明"以下总结仅基于会中事件流，未成功读取共享文档内容"。

### 7. 关于 `page_token` 的返回与续拉

- 不管这次是只查 1 页，还是通过 `page_all=true` 已经把当前可见事件都拿完，都应把最后拿到的 `page_token` 一并保留下来并返回给用户。
- 只要响应里出现 `has_more=true`、pretty 里出现 `more available`，或返回了非空 `page_token`，就必须先判断当前结果是否完整；默认情况下，这意味着你还需要继续分页。
- 如果没有使用 `page_all=true`，但出现了上述分页信号，默认应继续用返回的 `page_token` 拉下一页，而不是直接结束。只有在用户明确不要继续翻页时，才可以停止并明确说明当前结果不完整。
- 下次继续"查新增事件"时，应优先复用上一次保存的 `page_token`，而不是从头全量再拉一次。
- 只有在用户明确要求"从头回放全部事件"时，才忽略历史 `page_token`，重新从第一页开始。
- 但如果用户要你回答的是**当前这场会正在讲什么**，而不是"上一次之后新增了什么"，也要先做一次新的事件查询，再决定是否需要基于旧 `page_token` 继续补拉。

## 返回结构

常见顶层字段：

| 字段 | 说明 |
|------|------|
| `events` | 事件列表 |
| `has_more` | 是否还有下一页 |
| `page_token` | 下一页游标 |

事件 `event_type` 常见类型：

| event_type | 含义 |
|-----------|------|
| `participant_joined` | 有参会人加入会议 |
| `participant_left` | 有参会人离开会议 |
| `chat_received` | 收到会中聊天消息 |
| `transcript_received` | 收到转写文本 |
| `magic_share_started` | 开始共享内容 / 文档 |
| `magic_share_ended` | 结束共享 |

## pretty 输出示例

```text
会议主题：张三的视频会议
会议时间：2026-04-17 15:28:52（进行中）

[00:00:33] 明日之虾BOE(ou_xxx) 加入了会议
[00:00:41] 张三(ou_xxx): [text] 6666
[00:00:44] 张三(ou_xxx) 开始共享《智能纪要：飞书20251022-140223 2026年3月9日》
           URL: https://...
[00:01:32] 张三(ou_xxx): [reaction] JIAYI
```

## 如何获取输入参数

| 输入参数 | 获取方式 |
|---------|---------|
| `meeting_id` | `lark_vc_meeting_join` 返回的 `meeting.id`；或 `lark_vc_search` 结果中的 `id` |
| `start` / `end` | 用户给出的时间范围；如未给出则默认取全量可见事件 |
| `page_token` | 上一页或上一次查询结果中保存的 `page_token`；建议持久化保存，便于下次继续拉取新增事件 |

## Agent 组合场景

### 场景 1：入会后查看会中发生了什么

```
# 第 1 步：加入会议，记录返回的 meeting.id
lark_vc_meeting_join(meeting_number="123456789")

# 第 2 步：查询事件流
lark_vc_meeting_events(meeting_id="<meeting.id>", page_all=true, format="pretty")
```

### 场景 2：过滤某段时间内的事件

```
lark_vc_meeting_events(meeting_id="<meeting.id>", start="2026-04-17T15:00:00+08:00", end="2026-04-17T16:00:00+08:00", page_all=true, format="pretty")
```

### 场景 3：基于上一次的 `page_token` 继续查新增事件

```
# 上一次查询结束后，保留最后返回的 page_token
# 这次直接从该游标继续拉新增事件
lark_vc_meeting_events(meeting_id="<meeting.id>", page_token="<last_page_token>", page_all=true, format="pretty")
```

适用规则：

- 当用户说"继续看新事件""看上次之后新增了什么"时，优先使用上一次保存的 `page_token`。
- 如果这次返回里仍有 `has_more=true`、pretty 里出现 `more available`，或又返回了新的 `page_token`，说明新增事件还没拉完，应继续分页，而不是把当前页误当成完整增量结果。
- 只有在用户明确要求"从头回放全部事件"时，才忽略已有 `page_token`，重新从第一页开始。

## 常见错误与排查

| 错误现象 | 根本原因 | 解决方案 |
|---------|---------|---------|
| `meeting_id is required` | 未传入 `meeting_id` | 传入长数字 `meeting.id` |
| `10005 bot is not in meeting` | bot 从未真实入会该会议；或会议已结束但 bot 从未在会中出现过 | 先 `lark_vc_meeting_join(meeting_number="<9位号>")` 真实入会再查；如果会议已经结束且当时 bot 没进过会，本接口也拉不到数据。**如果只是想看参会人快照，改用 `lark_invoke(tool_name="lark_vc_meeting_get", args={params: {"meeting_id": "<meeting.id>"}, with_participants: true})`**（不依赖 bot 身份参会） |
| `20001 meeting_status_MEETING_END` | 会议已结束且已超出后端允许的 5 分钟宽限窗口 | 本接口不再适合继续拉取事件。若要拿纪要文档或逐字稿 token，用 `lark_vc_notes(meeting_ids="<meeting.id>")`；若要拿 AI 产物（summary / todos / chapters）或导出逐字稿文件，先用 `lark_vc_recording(meeting_ids="<meeting.id>")` 拿 `minute_token`，再用 `lark_vc_notes(minute_tokens="<minute_token>")`；参会人请用 `lark_invoke(tool_name="lark_vc_meeting_get", args={params: {"meeting_id": "<meeting.id>"}, with_participants: true})` |
| `20002 meeting not exist` | `meeting_id` 错误，或会议实例当前已不可获取（常见于把 9 位会议号当 meeting_id 传） | 确认传入的是长数字 `meeting_id`，不是 9 位会议号 |
| `HTTP 404` / `HTTP 500` | 服务端当前无法找到或处理该会议实例 | 换一个正在进行且 bot 可见的 meeting_id，或排查后端问题 |

## 提示

- 这是**会中事件流**查询，不适合拿来搜历史会议记录；搜历史会议请用 `lark_vc_search`。
- 如果会议已经结束，不要卡在 `lark_vc_meeting_events`：  
  - 想拿纪要文档或逐字稿 token：用 `lark_vc_notes(meeting_ids="<meeting.id>")`
  - 想拿 AI 产物（summary / todos / chapters）或导出逐字稿文件：先用 `lark_vc_recording(meeting_ids="<meeting.id>")` 拿 `minute_token`，再用 `lark_vc_notes(minute_tokens="<minute_token>")`
- 事件列表是否完整，取决于 bot 何时入会、何时离会，以及后端当前可见的会中事件范围。对于已结束会议，通常只在**结束后 5 分钟内**、且 bot **曾经在会中**时还能继续拉到事件。
- 查询"谁参加过某会议"请用 `lark_invoke(tool_name="lark_vc_meeting_get", args={params: {"meeting_id": "<id>"}, with_participants: true})`——这是参会人**快照** API，不依赖 bot 是否参会，对已结束会议也可查；**不要** 用 `lark_vc_meeting_events` 做参会人查询。

## 参考

- `lark_get_skill(domain="vc-agent", section="meeting-join")` — 先真实入会
- `lark_get_skill(domain="vc-agent", section="meeting-leave")` — 用户明确要求时离会
- `lark_get_skill(domain="vc", section="search")` — 搜索历史会议（获取 meeting_id）
- `lark_get_skill(domain="vc", section="recording")` — 查询 minute_token
- `lark_get_skill(domain="vc", section="notes")` — 获取会议纪要
- `lark_get_skill(domain="vc-agent")` — Agent 参会能力（本 skill）
- `lark_get_skill(domain="vc")` — 视频会议原子域（Meeting / Note 等核心概念）
