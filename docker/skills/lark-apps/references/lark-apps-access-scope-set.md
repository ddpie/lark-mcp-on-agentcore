# apps +access-scope-set

设置应用的可用范围。三种 scope 形态互斥：`specific`（指定可见）、`public`（互联网公开）、`tenant`（企业全员）。

## 用法

```
# 指定可见 + 允许申请（targets 支持 user / department / chat 三种类型）
lark_apps_access_scope_set(app_id="app_xxx", scope="specific", targets='[{"type":"user","id":"ou_xxx"},{"type":"department","id":"od_xxx"},{"type":"chat","id":"oc_xxx"}]', apply_enabled=true, approver="ou_yyy")

# 互联网公开 + 免登
lark_apps_access_scope_set(app_id="app_xxx", scope="public", require_login=false)

# 企业全员
lark_apps_access_scope_set(app_id="app_xxx", scope="tenant")
```

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `app_id` | 是 | 应用 ID |
| `scope` | 是 | `specific` / `public` / `tenant` |
| `targets` | scope=specific 必填 | targets JSON 数组，每项 `{"type":"user\|department\|chat", "id":"<id>"}` |
| `apply_enabled` | scope=specific 可选 | 是否允许申请访问 |
| `approver` | `apply_enabled` 必填 | 申请审批人（**只能传一个 user open_id**，服务端限制） |
| `require_login` | scope=public 必填 | 是否要求登录 |

## 互斥校验（Validate 阶段，不通过直接报错不发请求）

- `scope=specific`：必传 `targets`；不允许 `require_login`
- `scope=public`：必传 `require_login`；不允许 `targets` / `apply_enabled` / `approver`
- `scope=tenant`：不允许任何其它 flag
- `targets` 内每项的 `type` 必须是 `user` / `department` / `chat` 之一

## 返回值

**成功：**

```json
{ "ok": true, "data": {} }
```

## 典型场景

### 场景 1：用户说"把应用 X 开放给全员"

```
lark_apps_access_scope_set(app_id="app_xxx", scope="tenant")
```

> 应用 `{app_id}` 可用范围已设为企业全员。

### 场景 2：用户说"把应用 X 设为互联网公开 + 免登"

```
lark_apps_access_scope_set(app_id="app_xxx", scope="public", require_login=false)
```

### 场景 3：用户说"只让 Alice 和 Bob 访问应用 X"

先用 `lark_get_skill(domain="contact")` 把姓名解析成 ou_id，再调：

```
lark_apps_access_scope_set(app_id="app_xxx", scope="specific", targets='[{"type":"user","id":"ou_alice"},{"type":"user","id":"ou_bob"}]')
```

## 参考

- `lark_get_skill(domain="apps")` — 妙搭应用全部命令
