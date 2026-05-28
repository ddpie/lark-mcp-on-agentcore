# apps +create

创建一个新的妙搭应用。返回新建应用的元信息。

## 用法

```
# 最小调用
lark_apps_create(name="客户调研问卷", app_type="HTML")

# 全参数
lark_apps_create(name="客户调研问卷", app_type="HTML", description="本季度客户满意度调研", icon_url="https://lf3-static.bytednsdoc.com/.../feisuda/avatar/5.svg")
```

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `name` | 是 | 应用显示名 |
| `app_type` | 是 | 应用类型，当前可选值：`HTML`（区分大小写；未来会扩展） |
| `description` | 否 | 应用描述 |
| `icon_url` | 否 | 应用图标 URL；不传服务端给默认图标 |

## 返回值

**成功：**

```json
{
  "ok": true,
  "data": {
    "app": {
      "app_id": "app_4k5jepcbjmv6m",
      "name": "客户调研问卷",
      "description": "本季度客户满意度调研",
      "icon_url": "https://lf3-static.bytednsdoc.com/.../feisuda/avatar/5.svg",
      "created_at": "2026-05-18T10:00:00Z"
    }
  }
}
```

**失败：**

```json
{
  "ok": false,
  "error": {
    "type": "api_error",
    "code": "api_error",
    "message": "...",
    "hint": "可执行的修复建议（可能为空）"
  }
}
```

## 字段语义

- `app_type` 是应用类型枚举，**区分大小写**，当前只允许 `HTML`，未来会扩展；不在白名单的取值会被直接拒绝
- `created_at` 是 ISO 8601 UTC 时间字符串
- `error.hint` 是可执行修复建议，**优先**转述给用户；hint 为空时退回 `error.message`
- 不要原样把 envelope JSON 复述给用户

## 参考

- `lark_get_skill(domain="apps")` — 妙搭应用全部命令
