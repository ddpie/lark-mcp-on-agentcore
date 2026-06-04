
# lark_vc_meeting_leave

(authentication is handled automatically by the MCP server)

通过 `meeting_id` 离开当前身份所在的视频会议（bot leave）。这是一次**写操作**，会实际把当前身份从会议中移出。

本工具对应 shortcut：`lark_vc_meeting_leave`（调用 `POST /open-apis/vc/v1/bots/leave`）。

## 调用方式

```
# 通过 meeting_id 离会
lark_vc_meeting_leave(meeting_id="69xxxxxxxxxxxxx28")

# 输出格式
lark_vc_meeting_leave(meeting_id="69xxxxxxxxxxxxx28", format="json")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `meeting_id` | 是 | 会议 ID（**不是 9 位会议号**） |
| `format` | 否 | 输出格式：json (默认) / pretty / table / ndjson / csv |

## 核心约束

### 1. 入参是 meeting_id，不是会议号

`meeting_id` 必须是会议的长数字 ID，通常由 `lark_vc_meeting_join` 返回体中的 `meeting.id` 提供，也可从 `lark_vc_search` 结果中的 `id` 字段获取。**传 9 位会议号会失败**。

### 2. 仅支持 user 身份

该工具仅支持 `user` 身份。只能让当前身份自己离会，无法强制移出其他参会人。

### 3. 当前身份必须在会议中

必须先通过 `lark_vc_meeting_join` 或其他方式在该会议中，否则接口会报错。

### 4. 离会立即生效，对其他参会人可见

机器人会立刻从参会列表消失；若会议启用了录制/纪要，bot 的参会时段到此截止。只有在用户明确要求退出 / 离开 / 结束参会时才调用；如需要重新入会，再跑 `lark_vc_meeting_join` 即可（非真正"不可逆"）。

## 输出结果

接口成功返回时，默认输出：`Left meeting <meeting-id> successfully.`。
`format="json"` 返回 API 原始响应体。

## 如何获取输入参数

| 输入参数 | 获取方式 |
|---------|---------|
| `meeting_id` | `lark_vc_meeting_join` 返回的 `meeting.id`；或 `lark_vc_search` 结果中的 `id` 字段 |

## Agent 组合场景

### 场景 1：加入 → 用户明确要求时离开

```
# 第 1 步：加入会议，记录 meeting.id
lark_vc_meeting_join(meeting_number="123456789")

# 第 2 步：在会中处理用户请求（如监听发言、记录信息等）
# ...

# 第 3 步：仅在用户明确要求退出 / 离开 / 结束参会时，使用上一步记录的 meeting.id 离会
lark_vc_meeting_leave(meeting_id="<meeting.id>")
```

### 场景 2：会后补拉产物（不需要离会）

如果用户只是要求会议结束后拉录制、纪要或逐字稿，不要先调用 `lark_vc_meeting_leave`；直接跨到 lark-vc 查询会后产物。

```
# 第 1 步：会议结束后查询录制
lark_vc_recording(meeting_ids="<meeting.id>")

# 第 2 步：查询会议纪要
lark_vc_notes(meeting_ids="<meeting.id>")
```

## 常见错误与排查

| 错误现象 | 根本原因 | 解决方案 |
|---------|---------|---------|
| `meeting_id is required` | 未传入 `meeting_id` | 传入从 `lark_vc_meeting_join` 得到的 `meeting.id` |
| `meeting not found` / `invalid meeting_id` | 误传了 9 位会议号 | 必须使用 `meeting.id`，不是会议号 |
| `not in meeting` | 当前身份并不在该会议中 | 确认先 `lark_vc_meeting_join` 成功 |

## 提示

- 只有用户明确要求退出 / 离开 / 结束参会时才调用；离会会让机器人从参会列表消失，对其他参会人可见。若需要重新入会直接再 `lark_vc_meeting_join`，不是真正的"不可逆"。
- `lark_vc_meeting_leave` 依赖 `lark_vc_meeting_join` 返回的 `meeting.id`，但不是每次 join 后都必须调用 leave。
- `meeting_id` 优先使用 `lark_vc_meeting_join` 返回的 `meeting.id`；如果来自 `lark_vc_search`，也必须先确认当前身份就在该会议中。不要用 9 位会议号。

## 参考

- `lark_get_skill(domain="vc-agent", section="meeting-join")` — 对应的入会工具
- `lark_get_skill(domain="vc-agent", section="meeting-events")` — 会中事件流
- `lark_get_skill(domain="vc", section="search")` — 搜索历史会议（获取 meeting_id）
- `lark_get_skill(domain="vc", section="recording")` — 查询 minute_token
- `lark_get_skill(domain="vc", section="notes")` — 获取会议纪要
- `lark_get_skill(domain="vc-agent")` — Agent 参会能力（本 skill）
- `lark_get_skill(domain="vc")` — 视频会议原子域（Meeting / Note 等核心概念）
