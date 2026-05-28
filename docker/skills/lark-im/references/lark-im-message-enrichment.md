# im default message enrichment (reactions / update_time)

This is the single source of truth for the automatic message-enrichment contract shared by the four message-pulling tools — `lark_im_messages_mget`, `lark_im_chat_messages_list`, `lark_im_messages_search`, `lark_im_threads_messages_list`. They automatically attach `reactions` and `update_time` to each returned message, so callers do **not** need to invoke the raw `im.reactions.batch_query` API separately.

- **`reactions`** — populated from one batched `im.reactions.batch_query` call as `{counts, details}`. The field is only attached when the server actually returns data; messages with no reactions omit it. Replies inside `thread_replies` are enriched in the **same batched call** as their parent, so outer and inner messages follow identical semantics.
- **`update_time`** — emitted only when `updated == true` (message was actually edited). The server echoes `update_time == create_time` for unedited messages too, but the tool gates that output away so consumers don't misread every message as "edited".
- **Opt-out** — each tool accepts `no_reactions=true` to skip the extra round-trip when the caller only needs message bodies.

## Scope requirement

The default enrichment requires `im:message.reactions:read`, already declared in each tool's scope configuration, so the framework's pre-flight check surfaces a `missing_scope` error before the request is sent. Bots that were registered before this scope was added need an incremental authorization in the Feishu developer console.

(Authentication is handled automatically by the MCP server.)

## Data contract — missing field ≠ fetch failure

| Situation | Output |
|---|---|
| Message has no reactions | `reactions` field is omitted (not `{}`, not an empty list) |
| Message was never edited | `update_time` field is omitted |
| Whole batch failed | Messages in that batch carry no `reactions`; one line on stderr: `warning: reactions_batch_query_failed: ...` |
| Some message IDs failed | Failed IDs go to stderr: `warning: reactions_partial_failed: N message(s) failed (...)` |

When deciding "has the user already reacted?", branch on the **presence of the `reactions` field plus its `counts` contents**, not on whether a value is `null` — the field's absence means "no data attached" (which usually means "no reactions exist"), not "fetch failed".
