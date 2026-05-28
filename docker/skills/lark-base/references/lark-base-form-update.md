# base +form-update

更新多维表格数据表中指定表单的名称或描述。

## 命令

```
# 更新表单名称
lark_base_form_update(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>", name="新表单名称")

# 更新描述（纯文本）
lark_base_form_update(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>", description="新的描述内容")

# 更新描述（含链接）
lark_base_form_update(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>", description=""新描述，[了解更多](https://example.com")

# 同时更新名称和描述
lark_base_form_update(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>", name="新表单名称", description="新的描述内容")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token（base_token） |
| `table_id <id>` | 是 | 数据表 ID |
| `form_id <id>` | 是 | 表单 ID |
| `name <name>` | 否 | 新的表单名称 |
| `description <string>` | 否 | 新的表单描述（纯文本或 Markdown 链接，如 `[文本](https://example.com)`） |
| `format` | 否 | 输出格式：json（默认）\| pretty \| table \| ndjson \| csv |
| `as` | 否 | 身份：user（默认）\| bot |

> `--name` 和 `--description` 至少传一个，否则无实际变更。

## 输出格式

返回更新后的表单信息：

```json
{
  "ok": true,
  "data": {
    "id": "vewX58te9D",
    "name": "新表单名称",
    "description": "新的描述内容"
  }
}
```

## 工作流

> [!CAUTION]
> 这是**写入操作** — 执行前必须向用户确认。

1. 确认 `form_id`（可通过 `+form-list` 获取）
2. 确认要修改的字段
3. 执行命令并报告更新后的值

## 参考

- `lark_get_skill(domain="base")` — 多维表格全部命令
