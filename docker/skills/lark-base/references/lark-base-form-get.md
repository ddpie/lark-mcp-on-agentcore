# base +form-get

获取多维表格数据表中指定表单的详情。只读操作，不修改任何数据。

## 命令

```
# 获取表单详情
lark_base_form_get(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>")

# 以 pretty 格式展示
lark_base_form_get(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>")

# 使用应用身份（bot）
lark_base_form_get(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token（base_token） |
| `table_id <id>` | 是 | 数据表 ID |
| `form_id <id>` | 是 | 表单 ID |
| `format` | 否 | 输出格式：json（默认）\| pretty \| table \| ndjson \| csv |
| `as` | 否 | 身份：user（默认）\| bot |

## 输出格式

| 字段 | 说明 |
|------|------|
| `id` | 表单 ID |
| `name` | 表单名称 |
| `description` | 表单描述 |

```json
{
  "ok": true,
  "data": {
    "id": "vewX58te9D",
    "name": "用户调研问卷",
    "description": "2024年度用户满意度调研"
  }
}
```

## 提示

- `form_id` 可通过 `lark_base_form_list(table_id="<id>", table_i=true)` 获取

## 参考

- `lark_get_skill(domain="base")` — 多维表格全部命令
