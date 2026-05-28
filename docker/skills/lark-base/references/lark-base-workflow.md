# base workflow shortcuts

workflow 相关命令索引。

## 命令导航

| 文档 | 命令 | 说明 |
|------|------|------|
| `lark_get_skill(domain="base", section="workflow-list")` | `+workflow-list` | 列出 Base 中所有自动化工作流 |
| `lark_get_skill(domain="base", section="workflow-get")` | `+workflow-get` | 获取单工作流的详情和完整结构 |
| `lark_get_skill(domain="base", section="workflow-create")` | `+workflow-create` | 创建一个新的自动化工作流 |
| `lark_get_skill(domain="base", section="workflow-update")` | `+workflow-update` | 全量替换已有工作流的定义 |
| `lark_get_skill(domain="base", section="workflow-enable")` | `+workflow-enable` | 启用一个自动化工作流 |
| `lark_get_skill(domain="base", section="workflow-disable")` | `+workflow-disable` | 禁用一个自动化工作流 |
| `lark_get_skill(domain="base", section="workflow-schema")` | (数据结构参考) | Workflow 的创建和更新结构规范 |

## 说明

- 聚合页只保留目录职责；每个命令的详细说明请进入对应单命令文档。
- **配置前置依赖**：在创建或更新 workflow 之前，大概率需要获取数据表（table）或字段（field）的真实 ID 等信息作为工作流节点的参数。建议按需先查阅 `lark_get_skill(domain="base", section="table")` 或 `lark_get_skill(domain="base", section="field")` 获取结构。
- **Schema 结构必读**：在创建或更新 workflow 前，必须仔细阅读 `lark_get_skill(domain="base", section="workflow-schema")` 了解各触发器和节点组件的具体结构。
