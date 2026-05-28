# approval (v4)

## API Resources

```
lark_discover(query="approval.<resource>.<method>")   # 调用 API 前必须先查看参数结构
lark_invoke(tool_name="lark_approval_<resource>_<method>", args={...}) # 调用 API
```

> **重要**：使用原生 API 时，必须先用 `lark_discover` 查看 `params` / `data` 参数结构，不要猜测字段格式。

### instances

  - `get` — 获取单个审批实例详情
  - `cancel` — 撤回审批实例
  - `cc` — 抄送审批实例
  - `initiated` — 查询用户的已发起列表

### tasks

  - `remind` — 催办审批人
  - `approve` — 同意审批任务
  - `reject` — 拒绝审批任务
  - `transfer` — 转交审批任务
  - `query` — 查询用户的任务列表
  - `add_sign` — 审批任务加签
  - `rollback` — 退回审批任务

## 权限表

| 方法 | 所需 scope |
|------|-----------|
| `instances.get` | `approval:instance:read` |
| `instances.cancel` | `approval:instance:write` |
| `instances.cc` | `approval:instance:write` |
| `instances.initiated` | `approval:instance:read` |
| `tasks.remind` | `approval:instance:write` |
| `tasks.approve` | `approval:task:write` |
| `tasks.reject` | `approval:task:write` |
| `tasks.transfer` | `approval:task:write` |
| `tasks.query` | `approval:task:read` |
| `tasks.add_sign` | `approval:task:write` |
| `tasks.rollback` | `approval:task:write` |
