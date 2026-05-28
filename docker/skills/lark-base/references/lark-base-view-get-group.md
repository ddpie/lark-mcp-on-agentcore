# base +view-get-group

获取分组配置。

## 推荐命令

```
lark_base_view_get_group(base_token="app_xxx", table_id="tbl_xxx", view_id="viw_xxx")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token |
| `table_id <id_or_name>` | 是 | 表 ID 或表名 |
| `view_id <id_or_name>` | 是 | 视图 ID 或视图名 |

## API 入参详情

**HTTP 方法和路径：**

```
GET /open-apis/base/v3/bases/:base_token/tables/:table_id/views/:view_id/group
```

## 返回重点

- 返回原始分组配置。

## 参考

- `lark_get_skill(domain="base", section="view")` — view 索引页
