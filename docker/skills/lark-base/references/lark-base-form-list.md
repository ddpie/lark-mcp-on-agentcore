# base +form-list

列出多维表格数据表中的所有表单。自动翻页，一次性返回全量结果。只读操作，不修改任何数据。

## 命令

```
# 列出指定数据表的所有表单
lark_base_form_list(base_token="<base_token>", table_id="<table_id>")

# 以表格形式展示
lark_base_form_list(base_token="<base_token>", table_id="<table_id>")

# 使用应用身份（bot）
lark_base_form_list(base_token="<base_token>", table_id="<table_id>")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token（base_token） |
| `table_id <id>` | 是 | 数据表 ID |
| `page_size <n>` | 否 | 每次请求的分页大小，默认 100，最大 100 |
| `format` | 否 | 输出格式：json（默认）\| pretty \| table \| ndjson \| csv |
| `as` | 否 | 身份：user（默认）\| bot |

## 输出格式

每条表单包含以下字段：

| 字段 | 说明 |
|------|------|
| `id` | 表单 ID（如 `vewX58te9D`） |
| `name` | 表单名称 |
| `description` | 表单描述 |

JSON 输出示例（`--format json`，默认）：

```json
{
  "ok": true,
  "data": {
    "forms": [
      {"id": "vewX58te9D", "name": "用户调研问卷", "description": "..."},
      {"id": "form_yyyy",  "name": "产品反馈表",   "description": "..."}
    ],
    "total": 2
  }
}
```

## 提示

- `base_token` 在多维表格 URL 中可找到（形如 `bascnXXXX`）
- `table_id` 可通过 `lark_base_table_list()` 获取
- 如无表单，输出 `forms: []`

## 参考

- `lark_get_skill(domain="base")` — 多维表格全部命令
