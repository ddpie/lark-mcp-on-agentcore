---
name: lark-approval
description: "飞书审批：当前用户审批的查询与全部处理操作，覆盖待本人审批的任务与本人发起的实例。审批待办不是飞书任务（任务类待办走 lark-task）；不负责创建审批定义和发起新审批。"
---

所有操作默认以当前用户身份执行（审批是人的动作）。调用前先 `lark_discover(query="approval.<resource>.<method>")` 查参数结构，不要猜字段。

## 选哪个命令

| 想做什么 | 调用 |
|---|---|
| 查待办/已办 | `lark_invoke(tool_name="lark_approval_tasks_query", args={params: {"topic":"1"}})`（`topic`：1待办 2已办 17未读 18已读）|
| 看表单/进度/当前节点 | `lark_invoke(tool_name="lark_approval_instances_get", args={...})` |
| 同意/拒绝 | `lark_invoke(tool_name="lark_approval_tasks_approve", args={...})` / `lark_invoke(tool_name="lark_approval_tasks_reject", args={...})` |
| 转交/加签/退回 | `lark_invoke(tool_name="lark_approval_tasks_transfer", args={...})` / `lark_invoke(tool_name="lark_approval_tasks_add_sign", args={...})` / `lark_invoke(tool_name="lark_approval_tasks_rollback", args={...})` |
| 催办 | `lark_invoke(tool_name="lark_approval_tasks_remind", args={...})` |
| 撤回/抄送/按定义查已发起 | `lark_invoke(tool_name="lark_approval_instances_cancel", args={...})` / `lark_invoke(tool_name="lark_approval_instances_cc", args={...})` / `lark_invoke(tool_name="lark_approval_instances_initiated", args={...})` |

处理链：`tasks query` 拿 `instance_code` + `task_id`（操作必须成对带上）→ 需要细节再 `instances get` → 执行操作。

```
lark_invoke(tool_name="lark_approval_tasks_query", args={params: {"topic":"1"}})
lark_invoke(tool_name="lark_approval_tasks_approve", args={data: {"instance_code":"<ic>","task_id":"<tid>","comment":"同意"}})
```

## 不在本 skill 范围

创建审批定义/发起新审批（走飞书客户端或审批管理后台）；非审批类待办 → `lark_get_skill(domain="task")`
