# apps +list

> **⚠️ Hidden 命令 —— 不对 Agent 暴露**：本工具从 Shortcuts 表中隐去，**Agent 不应主动调用**。
>
> 需要拿现有应用的 `app_id` 时让用户提供 **妙搭应用链接**（如 `https://miaoda.feishu.cn/app/app_xxxxxxxxxxxxx`）然后从 URL 中提取，或者让用户直接给 `app_id` 字符串。

列出当前用户名下的妙搭应用。**cursor 分页**：默认拉一页（`page_size=20`），通过 `page_token` 拉下一页。

## 用法

```
# 拉第一页（默认 page_size=20）
lark_apps_list()

# 自定义页大小
lark_apps_list(page_size="50")

# 翻页（拿上一次响应的 page_token）
lark_apps_list(page_token="eyJQaW5PcmRlciI6...")
```

## 参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `page_size` | 否 | `20` | 每页条数 |
| `page_token` | 否 | `""` | 翻页 cursor，从上次响应的 `data.page_token` 拿 |

## 返回值

**成功：**

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "app_id": "app_4k5jepcbjmv6m",
        "name": "客户调研问卷",
        "description": "...",
        "icon_url": "...",
        "created_at": "2026-05-18T10:00:00Z",
        "updated_at": "2026-05-18T10:05:00Z"
      }
    ],
    "page_token": "cursor_next_xxx",
    "has_more": true
  }
}
```

## 用途

本工具保留可供人类操作员手动调用（例如运维 / 调试场景）。**Agent 不应主动调用**：默认行为是 `lark_apps_create` 新建；要复用现有应用，**让用户给妙搭应用链接或 app_id**。

## 参考

- `lark_get_skill(domain="apps")` — 妙搭应用全部命令
