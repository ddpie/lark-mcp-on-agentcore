# base table shortcuts

table 相关命令索引。

## 命令导航

| 文档 | 命令 | 说明 |
|------|------|------|
| `lark_get_skill(domain="base", section="table-list")` | `+table-list` | 分页列出数据表 |
| `lark_get_skill(domain="base", section="table-get")` | `+table-get` | 获取单表概要、字段和视图 |
| `lark_get_skill(domain="base", section="table-create")` | `+table-create` | 创建数据表，可附带字段 / 视图 |
| `lark_get_skill(domain="base", section="table-update")` | `+table-update` | 重命名数据表 |
| `lark_get_skill(domain="base", section="table-delete")` | `+table-delete` | 删除数据表 |

## 说明

- 聚合页只保留目录职责；调用任一 table 命令前，务必先阅读对应单命令文档（本页不提供调用细节）。
- 所有 `+xxx-list` 调用都必须串行执行；若要批量跑多个 list 请求，只能串行执行。
