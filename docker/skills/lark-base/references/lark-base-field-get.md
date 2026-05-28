# base +field-get

获取一个字段的完整配置。

## 推荐命令

```
lark_base_field_get(base_token="app_xxx", table_id="tbl_xxx", field_id="fld_xxx")
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
GET /open-apis/base/v3/bases/:base_token/tables/:table_id/fields/:field_id
```

## 返回重点

- 返回完整字段配置，适合做更新前的基线。

## 坑点

- ⚠️ 重名字段场景下，建议优先传 `fld_xxx`。

## 参考

- `lark_get_skill(domain="base", section="field")` — field 索引页
