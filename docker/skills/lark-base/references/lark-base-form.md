# base form shortcuts

form 相关命令索引。

## 命令导航

| 文档 | 命令 | 说明 |
|------|------|------|
| `lark_get_skill(domain="base", section="form-list")` | `+form-list` | 分页列出表单 |
| `lark_get_skill(domain="base", section="form-get")` | `+form-get` | 获取表单详情（Base 内部路径） |
| `lark_get_skill(domain="base", section="form-detail")` | `+form-detail` | 通过分享链接获取表单详情（含题目列表） |
| `lark_get_skill(domain="base", section="form-create")` | `+form-create` | 创建表单 |
| `lark_get_skill(domain="base", section="form-update")` | `+form-update` | 更新表单 |
| `lark_get_skill(domain="base", section="form-delete")` | `+form-delete` | 删除表单 |

## 相关

- `lark_get_skill(domain="base", section="form-questions")` — 表单问题（表单字段）管理

## 说明

- 聚合页只保留目录职责；每个命令的详细说明请进入对应单命令文档。
- 所有 `+xxx-list` 调用都必须串行执行；若要批量跑多个 list 请求，只能串行执行。
