# base field shortcuts

field 相关命令索引。

## 命令导航

| 文档 | 命令 | 说明 |
|------|------|------|
| `lark_get_skill(domain="base", section="field-list")` | `+field-list` | 分页列字段 |
| `lark_get_skill(domain="base", section="field-get")` | `+field-get` | 获取单字段配置 |
| `lark_get_skill(domain="base", section="field-create")` | `+field-create` | 创建字段 |
| `lark_get_skill(domain="base", section="field-update")` | `+field-update` | 更新字段 |
| `lark_get_skill(domain="base", section="field-search-options")` | `+field-search-options` | 搜索选项字段候选值 |
| `lark_get_skill(domain="base", section="field-delete")` | `+field-delete` | 删除字段 |

## 说明

- 聚合页只保留目录职责；每个命令的详细说明请进入对应单命令文档。
- 所有 `+xxx-list` 调用都必须串行执行；若要批量跑多个 list 请求，只能串行执行。
- 写字段 JSON 前优先阅读 `lark_get_skill(domain="base", section="shortcut-field-properties")`。
- 涉及字段类型转换时，直接阅读 `lark_get_skill(domain="base", section="field-update")` 中的“字段类型变更规则”。
