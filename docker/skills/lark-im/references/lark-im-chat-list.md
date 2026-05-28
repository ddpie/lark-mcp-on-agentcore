# im +chat-list

List groups the current user (or bot) is a member of. Useful for enumerating "my chats" without a search keyword, or for bulk operations against the caller's chats. Supports pagination, sort order, and (user identity only) muted-chat filtering.

This tool maps to: `lark_im_chat_list` (internally calls `GET /open-apis/im/v1/chats`).

## Commands

```
# List the user's chats (default sort: ByCreateTimeAsc)
lark_im_chat_list()

# Sort by recent activity (most recently active first)
lark_im_chat_list(sort_type="ByActiveTimeDesc")

# Limit page size
lark_im_chat_list(page_size="50")

# Pagination
lark_im_chat_list(page_token="xxx")

# Drop muted chats (user identity only)
lark_im_chat_list(exclude_muted=true)

# JSON output
lark_im_chat_list(format="json")
```

## Parameters

| Parameter | Required | Limits | Description |
|------|------|------|------|
| `user_id_type` | No | `open_id` (default), `union_id`, `user_id` | ID type used for `owner_id` in the response |
| `sort_type` | No | `ByCreateTimeAsc` (default), `ByActiveTimeDesc` | Result ordering |
| `page_size` | No | 1-100, default 20 | Number of results per page |
| `page_token` | No | - | Pagination token from the previous response |
| `exclude_muted` | No | User identity only | Drop chats the current user has muted (do-not-disturb). Under bot identity, the flag is silently inactive; see "Filtering muted chats" below |
| `format` | No | - | Output as JSON |

> **Note:** Supports both user identity (default) and bot identity. When using bot identity, the app must have bot capability enabled.

## Output Fields

| Field | Description |
|------|------|
| `chat_id` | Chat ID (`oc_xxx` format) |
| `name` | Chat name |
| `description` | Chat description |
| `owner_id` | Owner ID (type controlled by `user_id_type`) |
| `external` | Whether the chat is external |
| `chat_status` | Chat status (`normal` / `dissolved` / `dissolved_save`) |

## Filtering muted chats

`exclude_muted` (user identity only) drops chats the current user has set to do-not-disturb. After the list call, the tool batches the page's chat_ids through `POST /open-apis/im/v1/chat_user_setting/batch_get_mute_status` and filters client-side. Under bot identity, the mute API is UAT-only and the filter is silently skipped.

When the flag is set, the JSON envelope gains a `filter` sub-object (absent otherwise, so existing consumers are unaffected); `fetched_count == returned_count + filtered_count` always holds:

```json
{
  "chats": [...],
  "filter": {
    "applied": "exclude_muted",
    "fetched_count": 20,
    "returned_count": 17,
    "filtered_count": 3,
    "hint": "Filtered out 3 muted chat(s) on this page (17 remaining); use page_token to fetch more."
  }
}
```

## Usage Scenarios

### Scenario 1: List my recent chats

```
lark_im_chat_list(sort_type="ByActiveTimeDesc", page_size="10")
```

### Scenario 2: List my non-muted chats sorted by activity

```
lark_im_chat_list(sort_type="ByActiveTimeDesc", exclude_muted=true)
```

## Common Errors and Troubleshooting

| Symptom | Root Cause | Solution |
|---------|---------|---------|
| `page_size must be an integer between 1 and 100` | page-size is out of range or not an integer | Use an integer between 1 and 100 |
| Permission denied (99991672) | The bot app does not have `im:chat:read` TAT permission enabled | Enable the permission for the app in the Open Platform console |
| Permission denied (99991679) with user identity | UAT is not authorized for `im:chat:read` | Ensure the scope is authorized |
| `Bot ability is not activated` (232025) | The app does not have bot capability enabled | Enable bot capability in the Open Platform console |
| `exclude_muted` returns all chats unfiltered and `hint` says "no effect under bot identity" | Running under bot identity (mute API is UAT-only) | Switch to user identity for mute filtering |
