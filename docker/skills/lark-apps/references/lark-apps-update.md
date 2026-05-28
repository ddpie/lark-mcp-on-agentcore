# apps +update

部分更新一个妙搭应用的元信息（名字 / 描述）。**只把传入的字段发给服务端，未传字段保持不变**。

## 用法

```
lark_apps_update(app_id="app_xxx", name="调研问卷 v2")
lark_apps_update(app_id="app_xxx", description="新描述")
lark_apps_update(app_id="app_xxx", name="v2", description="新描述")
```

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `app_id` | 是 | 应用 ID |
| `name` | 否 | 新名字 |
| `description` | 否 | 新描述 |

`name` 和 `description` 至少传一个，否则 Validate 阶段报错。

## 返回值

**成功：**

```json
{
  "ok": true,
  "data": {
    "app": {
      "app_id": "app_4k5jepcbjmv6m",
      "name": "调研问卷 v2",
      "description": "...",
      "icon_url": "https://lf3-static.bytednsdoc.com/.../feisuda/avatar/5.svg",
      "created_at": "2026-05-18T10:00:00Z",
      "updated_at": "2026-05-18T10:05:00Z"
    }
  }
}
```

## 字段语义

- 响应 `data.app` 含完整应用对象（所有字段），不只是被改的
- `created_at` / `updated_at` 都是 ISO 8601 UTC 时间字符串
- 失败时优先转述 `error.hint`

## 参考

- `lark_get_skill(domain="apps")` — 妙搭应用全部命令
