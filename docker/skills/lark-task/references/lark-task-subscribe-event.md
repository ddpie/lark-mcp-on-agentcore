# task +subscribe-event

> **⚠️ Note:** This tool supports both user identity and bot identity. With user identity, it subscribes the current user's accessible tasks; with bot identity, it subscribes tasks the application is responsible for.

Subscribe task update events with the current identity.

This tool is different from `event +subscribe`:
- `task +subscribe-event` registers task-event access for the **current identity**
- with user identity, it subscribes the **current user** to task events for tasks they created, are responsible for, or follow
- with bot identity, it subscribes using the **application identity** for tasks the application is responsible for

> ⚠️ Bot identity subscription is not available via the MCP server (which always uses user identity). Only user identity subscriptions are supported.

The task event type is:

```text
task.task.update_user_access_v2
```

Within this event, task changes are represented by commit types (string values). Deduped list:

```text
task_assignees_update
task_completed_update
task_create
task_deleted
task_desc_update
task_followers_update
task_reminders_update
task_start_due_update
task_summary_update
```

Event payload shape (example):

```json
{
  "event_id": "evt_xxx",
  "event_types": ["task_summary_update"],
  "task_guid": "task_guid_xxx",
  "timestamp": "1775793266152",
  "type": "task.task.update_user_access_v2"
}
```

- `type`: event type, should be `task.task.update_user_access_v2`
- `event_id`: unique event id (useful for dedup)
- `event_types`: list of commit types (see the deduped list above)
- `task_guid`: the task GUID that changed
- `timestamp`: event timestamp (ms)

In practice, with user identity, the subscribed user can receive updates for tasks visible to them through authorship, assignment, or following.

## Recommended Usage

```
lark_task_subscribe_event()
```

## Parameters

This tool has no additional parameters.

## Workflow

1. Confirm that the user wants to subscribe to task events.
2. Execute `lark_task_subscribe_event()`
3. Report whether the subscription succeeded.

> [!CAUTION]
> This is a **Write Operation** -- You must confirm the user's intent before executing.
