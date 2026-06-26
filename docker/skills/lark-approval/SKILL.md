---
name: lark-approval
description: "飞书审批：查询和处理审批待办/已办/实例，搜索可发起审批定义、查看定义详情并发起原生审批实例。当用户要处理审批任务、查看审批实例、搜索或发起审批时使用。审批待办不是飞书任务；非审批类待办走 lark-task。不负责创建审批定义；三方审批定义不走原生提单。"
---

所有操作默认以当前用户身份执行（审批是人的动作）。调用前先 `lark_discover(query="approval.<resource>.<method>")` 查参数结构，不要猜字段。

## 选哪个命令

| 想做什么 | 调用 |
|---|---|
| 搜可发起定义 | `lark_invoke(tool_name="lark_approval_approvals_search", args={...})` |
| 看审批定义详情/提单前确认表单与流程 | `lark_invoke(tool_name="lark_approval_approvals_get", args={...})` |
| 发起原生审批实例 | `lark_invoke(tool_name="lark_approval_instances_create", args={...})` |
| 查待办/已办 | `lark_invoke(tool_name="lark_approval_tasks_query", args={params: {"topic":"1"}})`（`topic`：1待办 2已办 17未读 18已读）|
| 看表单/进度/当前节点 | `lark_invoke(tool_name="lark_approval_instances_get", args={...})` |
| 同意/拒绝 | `lark_invoke(tool_name="lark_approval_tasks_approve", args={...})` / `lark_invoke(tool_name="lark_approval_tasks_reject", args={...})` |
| 转交/加签/退回 | `lark_invoke(tool_name="lark_approval_tasks_transfer", args={...})` / `lark_invoke(tool_name="lark_approval_tasks_add_sign", args={...})` / `lark_invoke(tool_name="lark_approval_tasks_rollback", args={...})` |
| 催办 | `lark_invoke(tool_name="lark_approval_tasks_remind", args={...})` |
| 撤回/抄送/按定义查已发起 | `lark_invoke(tool_name="lark_approval_instances_cancel", args={...})` / `lark_invoke(tool_name="lark_approval_instances_cc", args={...})` / `lark_invoke(tool_name="lark_approval_instances_initiated", args={...})` |

处理链：

- 发起审批：`approvals search` -> `approvals get` -> `instances create`
- 处理审批：`tasks query` 拿 `instance_code` + `task_id`（操作必须成对带上）→ 需要细节再 `instances get` → 执行操作

```
lark_invoke(tool_name="lark_approval_approvals_search", args={data: {"keyword":"请假"}})
lark_invoke(tool_name="lark_approval_approvals_get", args={params: {"approval_code":"<code>"}})
lark_invoke(tool_name="lark_approval_instances_create", args={data: {"approval_code":"<code>","form":"[...]"}})
lark_invoke(tool_name="lark_approval_tasks_query", args={params: {"topic":"1"}})
lark_invoke(tool_name="lark_approval_tasks_approve", args={data: {"instance_code":"<ic>","task_id":"<tid>","comment":"同意"}})
```

## 发起原生审批

发起审批属于高风险写操作，按下表处理：

| 规则 | 处理 |
|---|---|
| 用户意图是发起审批 / 提单 / 提交请假审批 / 提交报销审批 / 创建审批实例 | 先调用 `lark_get_skill(domain="approval", section="initiate")`、`lark_get_skill(domain="approval", section="instance-form-control-parameters")` 和 `lark_get_skill(domain="approval", section="instance-value-sourcing")`，并 `lark_discover(query="approval.instances.create")` |
| 编排顺序 | 固定走 `approvals search` -> `approvals get` -> `instances create`；未拿到定义详情前不要猜 `form`、`node_approver_list` 或 `node_cc_list` |
| 三方定义 | `is_external=true` 时不要调用 `lark_approval_instances_create`，返回 `create_link` 并说明需通过链接发起 |
| 表单与节点参数 | 控件 `value` 结构看 `lark_get_skill(domain="approval", section="instance-form-control-parameters")`；值来源看 `lark_get_skill(domain="approval", section="instance-value-sourcing")` |
| 真正执行前 | 让用户确认最终定义、表单值和节点参数；成功后回报 `instance_code` 与 `instance_link` |

## 不在本 skill 范围

创建审批定义（走飞书客户端或审批管理后台）；三方定义发起（返回 `create_link`，引导用户通过链接发起）；非审批类待办 → `lark_get_skill(domain="task")`
