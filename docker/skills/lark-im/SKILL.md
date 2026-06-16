---
name: lark-im
description: "飞书即时通讯：收发消息和管理群聊。发送和回复消息、搜索聊天记录、管理群聊成员、上传下载图片和文件（支持大文件分片下载）、管理表情回复、发送应用内/短信/电话加急。当用户需要发消息、查看或搜索聊天记录、下载聊天中的文件、查看群成员、搜索群、创建群聊或话题群、管理标记数据、管理 Feed 置顶（添加/移除/查询置顶会话）、管理标签数据时使用。"
---

# im (v1)

## Core Concepts

- **Message**: A single message in a chat, identified by `message_id` (om_xxx). Supports types: text, post, image, file, audio, video, sticker, interactive (card), share_chat, share_user, merge_forward, etc.
- **Chat**: A group chat or P2P conversation, identified by `chat_id` (oc_xxx).
- **Thread**: A reply thread under a message, identified by `thread_id` (om_xxx or omt_xxx).
- **Reaction**: An emoji reaction on a message.
- **Flag**: A bookmark on a message or thread.
- **Feed Shortcut**: A chat pinned to the current user's feed sidebar, identified by `feed_card_id` (an `oc_xxx` open_chat_id for CHAT type).
- **Feed Group**: A tag that groups feed cards in the feed list, identified by `feed_group_id` (ofg_xxx). Members are feed cards, each identified by `feed_id` + `feed_type`. Two types: `normal` (members managed explicitly) and `rule` (members auto-derived from rules).

## Resource Relationships

```
Chat (oc_xxx)
├── Message (om_xxx)
│   ├── Thread (reply thread)
│   ├── Reaction (emoji)
│   └── Resource (image / file / video / audio)
└── Member (user / bot)
```

## Important Notes

### Identity and Token Mapping

- User identity uses `user_access_token`. Calls run as the authorized end user, so permissions depend on both the app scopes and that user's own access to the target chat/message/resource.
- Bot identity uses `tenant_access_token`. Calls run as the app bot, so behavior depends on the bot's membership, app visibility, availability range, and bot-specific scopes.
- If an IM API says it supports both `user` and `bot`, the token type changes who the operator is. The same API can succeed with one identity and fail with the other because owner/admin status, chat membership, tenant boundary, or app availability are checked against the current caller.

### Sender Name Resolution with Bot Identity

When using bot identity to fetch messages (e.g. `lark_im_chat_messages_list`, `lark_im_threads_messages_list`, `lark_im_messages_mget`), sender names may not be resolved (shown as open_id instead of display name). This happens when the bot cannot access the user's contact info.

**Root cause**: The bot's app visibility settings do not include the message sender, so the contact API returns no name.

**Solution**: Check the app's visibility settings in the Lark Developer Console — ensure the app's visible range covers the users whose names need to be resolved. Alternatively, use user identity to fetch messages, which typically has broader contact access.

### Default message enrichment (reactions / update_time)

The four message-pulling shortcuts (`lark_im_messages_mget`, `lark_im_chat_messages_list`, `lark_im_messages_search`, `lark_im_threads_messages_list`) automatically attach a `reactions` block and (for edited messages) `update_time` to each returned message — no separate `im.reactions.batch_query` call is needed. Pass `no_reactions=true` to opt out. For the full contract (output shape, the `im:message.reactions:read` scope requirement, and the "missing field ≠ fetch failure" data rules), call `lark_get_skill(domain="im", section="message-enrichment")`.

### Opt-in resource auto-download (`download_resources`)

`lark_im_chat_messages_list`, `lark_im_messages_mget`, and `lark_im_threads_messages_list` accept `download_resources=true` (**off by default** — no `resources` block and no extra requests when omitted). When set, eligible message resources (image/file/audio/video/media + post-embedded; **stickers excluded**) are downloaded into `./lark-im-resources/` and each message gains a `resources` array of `{message_id, key, type, local_path, size_bytes}`. Downloads are deduped by `(message_id, file_key)`, run with bounded concurrency, and isolate single-resource failures (`error: true` + stderr warning). **Scope:** requires `im:message:readonly` (already declared by the listing commands — no extra scope); works under both user and bot identity. For one-off downloads use `lark_im_messages_resources_download`. Full contract: `lark_get_skill(domain="im", section="message-enrichment")`.

### Card Messages (Interactive)

Card messages (`interactive` type) are not yet supported for compact conversion in event subscriptions. The raw event data will be returned instead, with a hint printed to stderr.

### Flag Types

Flags support two layers:

- **Message-layer flag**: `(ItemTypeDefault, FlagTypeMessage)` — regular message bookmark
- **Feed-layer flag**: `(ItemTypeThread/ItemTypeMsgThread, FlagTypeFeed)` — thread as feed-layer bookmark

Item types for feed-layer flags:
- **ItemTypeThread** (4) = thread in a topic-style chat
- **ItemTypeMsgThread** (11) = thread in a regular chat

### Feed Shortcut

Feed shortcuts add chats to the current user's feed sidebar. They are distinct from flags:

- **Flag** = bookmark on a message/thread, scoped to the user's bookmark list.
- **Feed shortcut** = entry in the user's feed sidebar (currently only chats).

Key limits:
- Only **CHAT-type** (`feed_card_id` is `oc_xxx`) is exposed via OpenAPI; doc/app/subscription shortcuts exist internally but are not yet whitelisted.
- All three operations (create/remove/list) are **user-identity only** — they sign with `user_access_token`.
- Batch size is **10 per call** for create/remove; list is a one-page wrapper with opaque `page_token` pagination.

## Shortcuts（推荐优先使用）

Shortcut 是对常用操作的高级封装。有 Shortcut 的操作优先使用。

| Shortcut | 说明 |
|----------|------|
| `lark_get_skill(domain="im", section="chat-create")` | Create a group chat or topic chat; user/bot; chat_mode group|topic; private/public; invites users/bots; optionally sets bot manager |
| `lark_get_skill(domain="im", section="chat-list")` | List chats the current user/bot is a member of; defaults to groups; pass types=p2p,group to include p2p single chats (user-only); user/bot; supports sorting, pagination, exclude_muted (user-only) |
| `lark_get_skill(domain="im", section="chat-messages-list")` | List messages in a chat or P2P conversation; user/bot; accepts chat_id or user_id, resolves P2P chat_id, supports time range/sort/pagination |
| `lark_get_skill(domain="im", section="chat-search")` | Search visible group chats by query keyword and/or member_ids; user/bot; e.g. look up chat_id by group name; supports type filters, sorting, pagination, and exclude_muted (user identity only) |
| `lark_get_skill(domain="im", section="chat-update")` | Update group chat name or description; user/bot; updates a chat's name or description |
| `lark_get_skill(domain="im", section="messages-mget")` | Batch get messages by IDs; user/bot; fetches up to 50 om_ message IDs, formats sender names, expands thread replies |
| `lark_get_skill(domain="im", section="messages-reply")` | Reply to a message (supports thread replies); user/bot; supports text/markdown/post/media replies, reply-in-thread, idempotency key |
| `lark_get_skill(domain="im", section="messages-resources-download")` | Download images/files from a message; user/bot; supports automatic chunked download for large files (8MB chunks), auto-detects file extension from Content-Type |
| `lark_get_skill(domain="im", section="messages-search")` | Search messages across chats (supports keyword, sender, time range filters) with user identity; user-only; filters by chat/sender/attachment/time, supports auto-pagination via `page_all` / `page_limit`, enriches results via batched mget and chats batch_query |
| `lark_get_skill(domain="im", section="messages-send")` | Send a message to a chat or direct message; user/bot; sends to chat_id or user_id with text/markdown/post/media, supports idempotency key |
| `lark_get_skill(domain="im", section="threads-messages-list")` | List messages in a thread; user/bot; accepts om_/omt_ input, resolves message IDs to thread_id, supports sort/pagination |
| `lark_get_skill(domain="im", section="flag-create")` | Create a bookmark on a message; user-only; defaults to message-layer flag; use flag_type="feed" for feed-layer flag (item_type auto-detected from chat mode) |
| `lark_get_skill(domain="im", section="flag-cancel")` | Cancel (remove) a bookmark. When no flag_type is given, best-effort double-cancel: removes message layer and (when chat_type is determinable) feed layer |
| `lark_get_skill(domain="im", section="flag-list")` | List bookmarks; user-only; auto-enriches feed-type thread entries with message content; supports `page_all` auto-pagination |
| `lark_get_skill(domain="im", section="feed-shortcut-create")` | Add chats to the user's feed shortcuts; user-only; oc_xxx chat IDs only; batch up to 10 per call; `head`/`tail` controls insertion order; partial failures return an `ok:false` ledger |
| `lark_get_skill(domain="im", section="feed-shortcut-remove")` | Remove chats from the user's feed shortcuts; user-only; batch up to 10 per call; removing an absent shortcut is idempotent success; real per-item failures return an `ok:false` ledger |
| `lark_get_skill(domain="im", section="feed-shortcut-list")` | List one page of the user's feed shortcuts; user-only; omit `page_token` for the first page; default output enriches CHAT entries under `detail`; pass `no_detail=true` to skip the extra lookup and `im:chat:read` scope |
| `lark_get_skill(domain="im", section="feed-group-list")` | List the caller's feed groups (tags); user-only; supports `page_all` auto-pagination |
| `lark_get_skill(domain="im", section="feed-group-list-item")` | List feed cards in a feed group (tag); user-only; enriches each item with chat_name resolved from feed_id; supports page_all auto-pagination |
| `lark_get_skill(domain="im", section="feed-group-query-item")` | Look up specific feed cards in a feed group (tag) by ID; user-only; enriches each item with chat_name resolved from feed_id |

## API Resources

```
lark_discover(query="im.<resource>.<method>")   # 调用 API 前必须先查看参数结构
lark_invoke(tool_name="lark_im_<resource>_<method>", args={...}) # 调用 API
```

> **重要**：使用原生 API 时，必须先调用 `lark_discover` 查看 `data` / `params` 参数结构，不要猜测字段格式。

### chats

  - `create` — 创建群。Identity: `bot` only (`tenant_access_token`). ⚠️ This operation requires bot identity and is not available via the MCP server.
  - `get` — 获取群信息。Identity: supports `user` and `bot`; the caller must be in the target chat to get full details, and must belong to the same tenant for internal chats.
  - `link` — 获取群分享链接。Identity: supports `user` and `bot`; the caller must be in the target chat, must be an owner or admin when chat sharing is restricted to owners/admins, and must belong to the same tenant for internal chats.
  - `update` — 更新群信息。Identity: supports `user` and `bot`.

### chat.members

  - `bots` — 获取群内机器人列表。Identity: supports `user` and `bot`; the caller must be in the target chat and must belong to the same tenant for internal chats.
  - `create` — 将用户或机器人拉入群聊。Identity: supports `user` and `bot`; the caller must be in the target chat; for `bot` calls, added users must be within the app's availability; for internal chats the operator must belong to the same tenant; if only owners/admins can add members, the caller must be an owner/admin, or a chat-creator bot with `im:chat:operate_as_owner`.
  - `delete` — 将用户或机器人移出群聊。Identity: supports `user` and `bot`; only group owner, admin, or creator bot can remove others; max 50 users or 5 bots per request.
  - `get` — 获取群成员列表。Identity: supports `user` and `bot`; the caller must be in the target chat and must belong to the same tenant for internal chats.

### chat.user_setting

  - `batch_query` — 批量查询当前用户在群内的个人偏好设置 (e.g. `is_muted` mutes normal messages, `is_mute_at_all` mutes @all messages); up to 10 chats per request. Identity: `user` only (`user_access_token`); the caller must be in each target chat.
  - `batch_update` — 批量更新当前用户在群内的个人偏好设置 (e.g. `is_muted` mutes normal messages, `is_mute_at_all` mutes @all messages); up to 10 chats per request. Identity: `user` only (`user_access_token`); the caller must be in each target chat.

### chat.managers

  - `add_managers` — 指定群管理员。Identity: supports `user` and `bot`; only the group owner can add managers; max 10 managers per chat (20 for super-large chats), and at most 5 bots per request.
  - `delete_managers` — 删除群管理员。Identity: supports `user` and `bot`; only the group owner can remove managers; max 50 users or 5 bots per request.

### chat.moderation

  - `get` — 获取群成员发言权限。Identity: supports `user` and `bot`; the caller must be in the target chat and belong to the same tenant.
  - `update` — 更新群发言权限。Identity: supports `user` and `bot`; only the group owner (or creator bot with `im:chat:operate_as_owner`) can update; the caller must be in the chat.

### messages

  - `delete` — 撤回消息。Identity: supports `user` and `bot`; for `bot` calls, the bot must be in the chat to revoke group messages; to revoke another user's group message, the bot must be the owner, an admin, or the creator; for user P2P recalls, the target user must be within the bot's availability.
  - `forward` — 转发消息。Identity: supports `user` and `bot`.
  - `merge_forward` — 合并转发消息。⚠️ This operation requires bot identity and is not available via the MCP server.
  - `read_users` — 查询消息已读信息。⚠️ This operation requires bot identity and is not available via the MCP server.
  - `urgent_app` — 发送应用内加急。⚠️ This operation requires bot identity and is not available via the MCP server.
  - `urgent_phone` — 发送电话加急。⚠️ This operation requires bot identity and is not available via the MCP server.
  - `urgent_sms` — 发送短信加急。⚠️ This operation requires bot identity and is not available via the MCP server.

### reactions

  - `batch_query` — 批量获取消息表情。Identity: supports `user` and `bot`. [Must-read] `lark_get_skill(domain="im", section="reactions")`
  - `create` — 添加消息表情回复。Identity: supports `user` and `bot`; the caller must be in the conversation that contains the message. [Must-read] `lark_get_skill(domain="im", section="reactions")`
  - `delete` — 删除消息表情回复。Identity: supports `user` and `bot`; the caller must be in the conversation that contains the message, and can only delete reactions added by itself. [Must-read] `lark_get_skill(domain="im", section="reactions")`
  - `list` — 获取消息表情回复。Identity: supports `user` and `bot`; the caller must be in the conversation that contains the message. [Must-read] `lark_get_skill(domain="im", section="reactions")`

### threads

  - `forward` — 转发话题。Identity: supports `user` and `bot`.

### images

  - `create` — 上传图片。⚠️ This operation requires bot identity and is not available via the MCP server.

### pins

  - `create` — Pin 消息。Identity: supports `user` and `bot`.
  - `delete` — 移除 Pin 消息。Identity: supports `user` and `bot`.
  - `list` — 获取群内 Pin 消息。Identity: supports `user` and `bot`.

### feed.groups

  - `batch_add_item` — Batch add feed cards to a feed group. Identity: `user` only (`user_access_token`). [Must-read] `lark_get_skill(domain="im", section="feed-groups")`
  - `batch_query` — Batch query feed groups. Identity: `user` only (`user_access_token`). [Must-read] `lark_get_skill(domain="im", section="feed-groups")`
  - `batch_remove_item` — Batch remove feed cards from a feed group. Identity: `user` only (`user_access_token`). [Must-read] `lark_get_skill(domain="im", section="feed-groups")`
  - `create` — Create a feed group. Identity: `user` only (`user_access_token`). [Must-read] `lark_get_skill(domain="im", section="feed-groups")`
  - `delete` — Delete a feed group. Identity: `user` only (`user_access_token`). [Must-read] `lark_get_skill(domain="im", section="feed-groups")`
  - `update` — Update a feed group. Identity: `user` only (`user_access_token`). [Must-read] `lark_get_skill(domain="im", section="feed-groups")`

## 权限表

| 方法 | 所需 scope |
|------|-----------|
| `chats.create` | `im:chat:create` |
| `chats.get` | `im:chat:read` |
| `chats.link` | `im:chat:read` |
| `chats.update` | `im:chat:update` |
| `chat.members.bots` | `im:chat.members:read` |
| `chat.members.create` | `im:chat.members:write_only` |
| `chat.members.delete` | `im:chat.members:write_only` |
| `chat.members.get` | `im:chat.members:read` |
| `chat.user_setting.batch_query` | `im:chat.user_setting:read` |
| `chat.user_setting.batch_update` | `im:chat.user_setting:write` |
| `chat.managers.add_managers` | `im:chat.managers:write_only` |
| `chat.managers.delete_managers` | `im:chat.managers:write_only` |
| `chat.moderation.get` | `im:chat.moderation:read` |
| `chat.moderation.update` | `im:chat:moderation:write_only` |
| `messages.delete` | `im:message:recall` |
| `messages.forward` | `im:message` |
| `messages.merge_forward` | `im:message` |
| `messages.read_users` | `im:message:readonly` |
| `messages.urgent_app` | `im:message.urgent` |
| `messages.urgent_phone` | `im:message.urgent:phone` |
| `messages.urgent_sms` | `im:message.urgent:sms` |
| `reactions.batch_query` | `im:message.reactions:read` |
| `reactions.create` | `im:message.reactions:write_only` |
| `reactions.delete` | `im:message.reactions:write_only` |
| `reactions.list` | `im:message.reactions:read` |
| `threads.forward` | `im:message` |
| `images.create` | `im:resource` |
| `pins.create` | `im:message.pins:write_only` |
| `pins.delete` | `im:message.pins:write_only` |
| `pins.list` | `im:message.pins:read` |
| `feed.groups.batch_add_item` | `im:feed_group_v1:write` |
| `feed.groups.batch_query` | `im:feed_group_v1:read` |
| `feed.groups.batch_remove_item` | `im:feed_group_v1:write` |
| `feed.groups.create` | `im:feed_group_v1:write` |
| `feed.groups.delete` | `im:feed_group_v1:write` |
| `feed.groups.update` | `im:feed_group_v1:write` |
