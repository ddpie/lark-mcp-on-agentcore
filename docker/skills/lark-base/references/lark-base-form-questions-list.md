# base +form-questions-list

列出多维表格表单/问卷中的所有问题。只读操作，不修改任何数据。

## 命令

```
# 列出表单所有问题
lark_base_form_questions_list(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>")

# 以表格形式展示
lark_base_form_questions_list(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>")

# 使用应用身份（bot）
lark_base_form_questions_list(base_token="<base_token>", table_id="<table_id>", form_id="<form_id>")
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

每条问题包含以下字段：

| 字段 | 说明 |
|------|------|
| `id` | 问题 ID（即数据表的 field_id） |
| `title` | 问题标题 |
| `description` | 问题描述 |
| `required` | 是否必填 |

```json
{
  "ok": true,
  "data": {
    "questions": [
      {
        "id": "q_001",
        "title": "您的姓名是？",
        "description": "请填写真实姓名",
        "required": true
      },
      {
        "id": "q_002",
        "title": "您的联系方式是？",
        "description": "手机号或邮箱",
        "required": false
      }
    ],
    "total": 2
  }
}
```

## 提示

- 问题 `id` 与数据表的 `field_id` 相同
- 返回的问题列表已按顺序排列

## 参考

- `lark_get_skill(domain="base")` — 多维表格全部命令
