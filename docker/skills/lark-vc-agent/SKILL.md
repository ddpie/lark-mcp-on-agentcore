---
name: lark-vc-agent
description: "飞书视频会议：让机器人代当前用户加入/离开正在进行的会议，并读取会议期间的实时事件（参会人加入与离开、发言、聊天、屏幕共享等）。1. 用户提供 9 位会议号、要求代为入会或离会时使用 lark_vc_meeting_join / lark_vc_meeting_leave——会真实产生入会/离会记录。2. 会议进行中用户想知道“谁加入了”“谁离开了”“谁在发言”“有人共享屏幕吗”等会中动态时，机器人入会后用 lark_vc_meeting_events 读取事件时间线。3. 典型场景：参会机器人、会中助手、代为旁听、代为参会。前提：机器人只能读到它自己参会过且仍在进行中的会议的事件；查询已结束会议的参会名单、纪要或逐字稿请使用 lark-vc 技能。"
---

# vc-agent (v1)

(authentication is handled automatically by the MCP server)

调用前先调用 `lark_get_skill(domain="vc")` 了解视频会议的核心概念（Meeting / Note / Minutes 等），本 skill 直接复用，不再重复定义。

## 内测提示

- 当前功能正在内测中，仅少数用户可用。
- 如果工具提示 `missing required scope(s)` / `permission_violations`，不要申请对应权限，而是提示用户加入早鸟群：`https://go.larkoffice.com/join-chat/2f4nb0e1-fe00-4f67-bed7-25beaf533fbd`。
- 如果工具返回 `error.code=20017` / `ErrNotInGray`，提示用户加入早鸟群：`https://go.larkoffice.com/join-chat/2f4nb0e1-fe00-4f67-bed7-25beaf533fbd`。

## 定位

本 skill 与 `lark-vc` 并列：

- **`lark-vc`** **负责"会后查询"**：搜索历史会议、参会人快照、纪要/逐字稿/录制
- **`lark-vc-agent`** **负责"会中动作"**：机器人入会 / 读取进行中会议的实时事件 / 机器人离会

按此分工路由，避免两个 skill 语义混淆。

| 用户意图示例                                                     | 应路由到                                                                                                                                                  |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| "帮我入会 123456789"、"代我参会"、"让机器人进会旁听"                         | **本 skill** `lark_vc_meeting_join`                                                                                                                           |
| "会议现在还开着，谁刚加入了"、"会议里谁在发言"、"有人共享屏幕吗"（**进行中会议**，且**机器人已入会**） | **本 skill** `lark_vc_meeting_events`                                                                                                                         |
| "退出会议"、"让机器人离开"                                            | **本 skill** `lark_vc_meeting_leave`                                                                                                                          |
| "昨天那场会有谁参加过"、"搜昨天的会"、"查纪要/逐字稿/录制"                          | `lark_get_skill(domain="vc")`                                                                                                                      |
| "帮我参会，结束后把纪要发到群" 等跨阶段场景                                    | 按序编排：本 skill（入会 → 读事件 → 离会）→ `lark_get_skill(domain="vc")` / `lark_get_skill(domain="minutes")`（拉纪要）→ `lark_get_skill(domain="im")`（发群） |

## 核心场景

### 1. 加入正在进行的会议（写操作）

1. 只有用户明确表达"让 Agent **真实入会**"（参会机器人、会中助手、代为旁听、代参会）时才用 `lark_vc_meeting_join`。只是查数据不要入会。
2. `lark_vc_meeting_join(meeting_number=...)` 只接受 **9 位纯数字**会议号，不是会议链接整串、也不是 `meeting_id`。
3. 返回体中的 `meeting.id` **必须立刻记录**——后续 `lark_vc_meeting_events` / `lark_vc_meeting_leave` 都靠它，**不能用 9 位会议号替代**。
4. 入会对所有参会人可见，执行前核实 9 位会议号来源，避免误入错会。
5. 仅支持 `user` 身份。
6. 若入会失败，优先查看 `lark_get_skill(domain="vc-agent", section="meeting-join")` 的错误排查段落，重点确认会议号、密码、会议状态、等候室 / 审批以及会议是否禁止当前身份加入。

### 2. 感知会中事件（读操作）

1. 用户要看"会议里正在发生什么"（参会人加入/离开、聊天、转写、屏幕共享）时，用 `lark_vc_meeting_events`。
2. 输入是 **`meeting_id`**（长数字 ID），不是 9 位会议号。
3. Bot 必须**真实参会过**（先 `lark_vc_meeting_join`），否则事件流通常不可见。具体的状态边界、结束后宽限窗口与错误码（如 `10005 / 20001 / 20002`）请查看 `lark_get_skill(domain="vc-agent", section="meeting-events")`。
4. **不能做会后复盘**，**不能替代参会人快照查询**。如果会议已结束：
   - 想拿纪要文档或逐字稿文档 token：用 `lark_vc_notes(meeting_ids="<meeting.id>")`
   - 想拿 AI 产物（summary / todos / chapters）或导出逐字稿文件：先用 `lark_vc_recording(meeting_ids="<meeting.id>")` 拿 `minute_token`，再用 `lark_vc_notes(minute_tokens="<minute_token>")`
   - 想看参会人快照：用 `lark_invoke(tool_name="lark_vc_meeting_get", args={params: {"meeting_id": "<meeting.id>"}, with_participants: true})`（见 `lark_get_skill(domain="vc")`）
5. **默认必须使用** `page_all=true`，除非用户明确要求"只查一页"，或确实需要控制返回体大小。
6. 输出格式默认优先 `format="pretty"`（时间线更易读）；只有在需要完整保留原始消息流与结构化字段时，才使用 `format="json"`。
7. **必须识别分页信号**：只要响应里出现 `has_more=true`、pretty 里的 `more available`，或返回了非空 `page_token`，就不能把当前结果当作完整事件流；默认应继续分页，或明确告诉用户当前只是部分结果。
8. 保留响应里的 `page_token`，下次增量拉取直接续，不要从头再拉。
9. **只要你是基于** `lark_vc_meeting_events` **来回答一场正在进行中的会议内容，就不能直接复用旧结果。** 无论用户是在问"现在/刚刚/最新"的状态，还是让你"总结一下这个会议讲什么"，都必须先重新拉一次当前事件流，确认拿到的是最新信息，再基于最新结果回答。只有在用户明确要求基于某次历史快照继续分析时，才可以复用旧结果。

### 3. 离开会议（写操作）

1. 任务完成、或用户要求结束时，用 `lark_vc_meeting_leave(meeting_id="<从 lark_vc_meeting_join 拿到的 meeting.id>")`。
2. `meeting_id` **必须**是 `lark_vc_meeting_join` 返回的长数字 `meeting.id`，**不接受 9 位会议号**。
3. 离会**立即生效**，机器人从会议的参会人列表中消失，对其他参会人可见；若需要重新入会，再跑一次 `lark_vc_meeting_join` 即可（非真正"不可逆"）。
4. 仅支持 `user` 身份。

### 4. Agent 参会最小闭环示范

```
# 1. 入会，捕获 meeting.id
lark_vc_meeting_join(meeting_number="123456789", format="json")
# → 从返回体中记录 meeting.id

# 2. 会中轮询事件
#    默认用 page_all=true 拉全当前可见事件；下次增量优先复用 page_token
#    典型间隔 10-30 秒
lark_vc_meeting_events(meeting_id="<MID>", page_all=true, format="pretty")

# 3. 任务完成或用户要求结束时离会
lark_vc_meeting_leave(meeting_id="<MID>")

# 4. 会后可选：取纪要 / 逐字稿（跨到 lark-vc）
lark_vc_notes(meeting_ids="<MID>")
```

## Shortcuts

Shortcut 是对常用操作的高级封装。

| Shortcut                                                        | 类型 | 说明                                                                         |
| --------------------------------------------------------------- | -- | -------------------------------------------------------------------------- |
| `lark_vc_meeting_join` | 写  | Join an in-progress meeting by 9-digit meeting number                      |
| `lark_vc_meeting_events` | 读  | List bot meeting events (participant joined/left, transcript, chat, share) |
| `lark_vc_meeting_leave` | 写  | Leave a meeting by meeting\_id                                             |

- 使用 `lark_vc_meeting_join` 前**必须**调用 `lark_get_skill(domain="vc-agent", section="meeting-join")`，了解入参格式与写操作可见性风险。
- 使用 `lark_vc_meeting_events` 前**必须**调用 `lark_get_skill(domain="vc-agent", section="meeting-events")`，了解 `meeting_id` 来源、分页、错误码（10005 / 20001 / 20002）与 "bot 仍在会中" 硬约束。
- 使用 `lark_vc_meeting_leave` 前**必须**调用 `lark_get_skill(domain="vc-agent", section="meeting-leave")`，了解 `meeting_id` 的来源与写操作可见性。

## 权限表

| Shortcut          | 所需 scope                       |
| ----------------- | ------------------------------ |
| `lark_vc_meeting_join`   | `vc:meeting.bot.join:write`    |
| `lark_vc_meeting_events` | `vc:meeting.meetingevent:read` |
| `lark_vc_meeting_leave`  | `vc:meeting.bot.join:write`    |

## 延伸

- 查已结束会议、参会人快照、搜索历史会议 → `lark_get_skill(domain="vc")`
- 会议纪要、逐字稿 → `lark_get_skill(domain="vc")` 的 `+notes`
- 妙记产物（AI 总结 / 转写 / 章节）→ `lark_get_skill(domain="minutes")`
- 会后把产物发到群 / 私聊 → `lark_get_skill(domain="im")`
