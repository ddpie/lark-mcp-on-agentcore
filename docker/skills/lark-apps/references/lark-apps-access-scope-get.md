# apps +access-scope-get

获取应用当前的可用范围配置。

## 用法

```
lark_apps_access_scope_get(app_id="app_xxx")
```

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `app_id` | 是 | 应用 ID |

## 返回值

**成功（specific，三种 target 类型混合）：**

```json
{
  "ok": true,
  "data": {
    "scope": "Range",
    "users": ["ou_xxx", "ou_yyy"],
    "departments": ["od_xxx"],
    "chats": ["oc_xxx"],
    "apply_config": {
      "enabled": true,
      "approvers": ["ou_approver"]
    }
  }
}
```

**成功（public + 免登）：**

```json
{ "ok": true, "data": { "scope": "All", "require_login": false } }
```

**成功（tenant）：**

```json
{ "ok": true, "data": { "scope": "Tenant" } }
```

## 字段语义

- `scope` 是**字符串枚举**：
  - `"All"` = 互联网公开 — 对应 `lark_apps_access_scope_set(scope="public")`
  - `"Tenant"` = 组织内 — 对应 `scope="tenant"`
  - `"Range"` = 部分人员 — 对应 `scope="specific"`
- `users` / `departments` / `chats` 三个数组（仅 `scope="Range"` 时）
- `apply_config`（可选，仅 `scope="Range"` 且申请开启时）：含 `enabled` 和 `approvers`（只允许一个 user open_id）
- `require_login`（仅 `scope="All"` 时）：bool

## 参考

- `lark_get_skill(domain="apps")` — 妙搭应用全部命令
