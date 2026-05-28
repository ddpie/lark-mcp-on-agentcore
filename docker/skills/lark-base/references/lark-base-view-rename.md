# base +view-rename

重命名一个视图。

## 推荐命令

```
lark_base_view_rename(base_token="app_xxx", table_id="tbl_xxx", view_id="viw_xxx", name="进行中客户")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token |
| `table_id <id_or_name>` | 是 | 表 ID 或表名 |
| `view_id <id_or_name>` | 是 | 视图 ID 或视图名 |
| `name <name>` | 是 | 新视图名 |

## API 入参详情

**HTTP 方法和路径：**

```
PATCH /open-apis/base/v3/bases/:base_token/tables/:table_id/views/:view_id
```

## 返回重点

- 返回更新后的 `view` 数据。

## 坑点

- ⚠️ 这是写入操作，执行前必须确认。

## 参考

- `lark_get_skill(domain="base", section="view")` — view 索引页
