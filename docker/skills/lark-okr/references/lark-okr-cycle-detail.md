# lark_okr_cycle_detail

列出指定 OKR 周期下的所有目标及其关键结果。

## 用法

```
# 列出指定周期的目标和关键结果
lark_okr_cycle_detail(cycle_id="1234567890123456789")
```

## 参数

| 参数           | 必填 | 默认值    | 说明                                      |
|--------------|----|--------|-----------------------------------------|
| `cycle_id` | 是  | —      | OKR 周期 ID（int64 类型）。从 `lark_okr_cycle_list` 获取。 |
| `format`   | 否  | `json` | 输出格式。                                   |

## 工作流程

1. 使用 `lark_okr_cycle_list` 获取 OKR 周期 ID。
2. 执行 `lark_okr_cycle_detail(cycle_id="123456")`。
3. 报告结果：找到的目标数量、每个目标的 ID、分数、权重及其关键结果。

## 输出

返回 JSON：

```json
{
  "cycle_id": "1234567890123456789",
  "objectives": [
    {
      "id": "2345678901234567890",
      "create_time": "2025-01-01 00:00:00",
      "update_time": "2025-01-15 12:00:00",
      "owner": {
        "owner_type": "user",
        "user_id": "ou_xxx"
      },
      "cycle_id": "1234567890123456789",
      "position": 0,
      "score": 0.75,
      "weight": 1.0,
      "deadline": "2025-06-30 23:59:59",
      "category_id": "cat_456",
      "content": "{...}",
      "notes": "{...}",
      "key_results": [
        {
          "id": "3456789012345678901",
          "create_time": "2025-01-01 00:00:00",
          "update_time": "2025-01-15 12:00:00",
          "owner": {
            "owner_type": "user",
            "user_id": "ou_xxx"
          },
          "objective_id": "2345678901234567890",
          "position": 0,
          "score": 0.8,
          "weight": 0.5,
          "deadline": "2025-06-30 23:59:59",
          "content": "{...}"
        }
      ]
    }
  ],
  "total": 1
}
```

其中，content 和 notes 字段是 JSON 字符串，为 OKR ContentBlock
富文本格式。请参考 `lark_get_skill(domain="okr", section="contentblock")` 了解详细信息。

## 参考

- `lark_get_skill(domain="okr")` -- 所有 OKR 工具(shortcut 和 API 接口)
