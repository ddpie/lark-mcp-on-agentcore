# base +field-delete

删除一个字段。

## 推荐命令

```
lark_base_field_delete(base_token="app_xxx", table_id="tbl_xxx", field_id="fld_xxx")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token |
| `table_id <id_or_name>` | 是 | 表 ID 或表名 |
| `field_id <id_or_name>` | 是 | 字段 ID 或字段名 |

## API 入参详情

**HTTP 方法和路径：**

```
DELETE /open-apis/base/v3/bases/:base_token/tables/:table_id/fields/:field_id
```

## 返回重点

- 返回 `deleted: true` 和目标字段标识。

## 工作流

> 这是**高风险写入操作**。server 对高风险操作需要 `_confirm=true`；如果用户已经明确要求删除且目标明确，直接执行并带上 `--yes`，不要再补一次确认。

1. 建议先用 `+field-get` 或 `+field-list` 确认目标字段。
2. 只有当字段目标仍不明确时，才继续追问；如果删除意图和目标都明确，直接执行。

## 坑点

- ⚠️ 高风险写操作，删除后不可恢复。
- ⚠️ 高风险操作需要 `_confirm=true`。

## 参考

- `lark_get_skill(domain="base", section="field")` — field 索引页
