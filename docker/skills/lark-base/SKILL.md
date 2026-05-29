---
name: lark-base
description: "操作飞书多维表格（Base）：搜索 Base、建表、字段管理、记录读写、记录分享链接、视图配置、历史查询，以及角色/表单/仪表盘管理/工作流。涉及字段设计、公式字段、查找引用、跨表计算、行级派生指标、数据分析需求时也必须使用本 skill。"
---

# base

> **执行前必做：** 执行任何 `base` 命令前，必须先阅读对应命令的 reference 文档，再调用命令。
> **查询类任务必做：** 涉及筛选、排序、Top/Bottom N、聚合、多表关联、查询后写入或判断全局结论时，必须先阅读 `lark_get_skill(domain="base", section="data-analysis-sop")`，再选择 `record / view / data-query` 路径。
> **命名约定：** Base 业务命令仅使用 `lark_base_*` 形式的 MCP tool；解析 Wiki 链接使用 `lark_wiki_node_get`。
> **分流规则：** 如果用户要“把本地文件导入成 Base / 多维表格 / bitable”，第一步不是 `base`，而是 `lark_drive_import()`；导入完成后再回到 `lark_base_*` 工具做表内操作。

## 1. 何时使用本 Skill

### 1.1 触发条件

以下场景应使用本 skill：

- 用户明确要操作飞书多维表格 / Base。
- 用户要建表、改表、查表、删表，或管理字段、记录、视图。
- 用户要做公式字段、lookup 字段、派生指标、跨表计算。
- 用户要做临时统计、聚合分析、比较排序、求最值。
- 用户要管理 workflow、dashboard、表单、角色权限。
- 用户给出 `/base/{token}` 链接。
- 用户给出 `/wiki/{token}` 链接，且最终解析为 `bitable`。
- 用户要把旧的 Base 聚合式写法改成当前原子命令写法，例如把旧 `+table / +field / +record / +view / +history / +workspace` 改写成当前命令。

以下场景不应使用本 skill：

- 用户只是做认证、初始化配置、切换身份、处理 scope。此时不需要本 skill。
- 用户只是泛化地讨论“数据分析 / 字段设计”，但并不在 Base 场景中。不要因为提到“统计 / 公式 / lookup”就误触发。

### 1.2 前置约束

1. MCP server 自动处理认证。
2. Base 业务命令仅使用 `lark_base_*` 形式的 MCP tool。
3. 如果输入是 Wiki 链接或 Wiki token，并且用户想读取/操作其中的 Base，先执行 `lark_wiki_node_get()`；当返回 `data.obj_type=bitable` 时，把 `data.obj_token` 当作 `--base-token`。不要把 URL 里的 `/wiki/{token}` 当成 Base token。（旧的 `--token` flag 仍可用，但已 deprecated，会在 stderr 打印迁移提示。）
4. 定位到命令后，先读该命令对应的 reference，再执行命令。
5. 如果用户要把本地 Excel / CSV / `.base` 快照导入成 Base / 多维表格 / bitable，第一步不是 `base`，而是 `lark_drive_import()`；导入完成后再回到 `lark_base_*` 工具做表内操作。
6. 不要在 Base 场景改走 裸 API 调用。
7. 如果用户只给 Base 名称、关键词，或说“帮我找一个多维表格”，先通过 `lark_drive_search(doc_types="bitable", doc_type=true)` 搜索 Base / 多维表格资源；拿到 Base URL 后再使用本 skill 的 `base +...` 命令。复杂搜索再读 `lark_get_skill(domain="drive", section="search")`：标题精确匹配、限定 owner（`--mine` / `--creator-ids`，owner 语义非"最初创建人"）/群/文件夹/时间范围、只搜标题/评论、分页/全量搜索。

## 2. 模块与命令导航

本章按“先选模块，再选命令”的方式组织。先判断用户目标属于哪个大模块，再进入对应子模块，按要求阅读 reference 后执行命令。

### 2.1 模块地图

| 大模块 | 处理什么问题 | 包含的小模块 / 能力 |
|------|-------------|-------------------|
| Base 模块 | 管理 Base 本体，或从链接进入 Base 场景 | `base-create / base-get / base-copy`，Base / Wiki 链接解析 |
| 表与数据模块 | 管理 Base 内部结构与日常数据操作 | `table / field / record / view` |
| 公式 / Lookup 模块 | 处理派生字段、条件判断、跨表计算、固定查找引用 | `formula / lookup` 字段创建与更新 |
| 数据分析模块 | 做一次性筛选、分组、聚合分析 | `data-query` |
| Workflow 模块 | 管理自动化流程 | `workflow-list / get / create / update / enable / disable` |
| Dashboard 模块 | 管理仪表盘和图表组件 | `dashboard-* / dashboard-block-*` |
| 表单模块 | 管理表单和表单题目 | `form-* / form-questions-*` |
| 权限与角色模块 | 管理高级权限和自定义角色 | `advperm-* / role-*` |

### 2.2 Base 模块

用于管理 Base 本体，或从用户给出的链接进入后续 Base 操作。  
模块索引：`lark_get_skill(domain="base", section="workspace")`

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `lark_drive_search(doc_types="bitable", doc_type=true)` | 按名称、关键词查找 Base / 多维表格 / bitable | 复杂搜索再读 `lark_get_skill(domain="drive", section="search")` | 先定位资源，再回到 `base +...` 操作表内数据 |
| `+base-create` | 创建新的 Base | `lark_get_skill(domain="base", section="base-create")`、`lark_get_skill(domain="base", section="workspace")` | 写入操作；执行前先读 reference；`--folder-token`、`--time-zone` 都是可选项 |
| `+base-get` | 获取 Base 信息 | `lark_get_skill(domain="base", section="base-get")`、`lark_get_skill(domain="base", section="workspace")` | 适合确认 Base 本体信息，不替代表/字段结构读取 |
| `+base-copy` | 复制已有 Base | `lark_get_skill(domain="base", section="base-copy")`、`lark_get_skill(domain="base", section="workspace")` | 写入操作；执行前先读 reference；复制成功后应主动返回新 Base 标识信息 |

### 2.3 表与数据模块

这是最常用的大模块，包含 `table / field / record / view` 四类子模块。  
补充示例：`lark_get_skill(domain="base", section="examples")`，适合需要串联 table / record / view 完整操作链路时再读。

#### 2.3.1 Table 子模块

子模块索引：`lark_get_skill(domain="base", section="table")`

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+table-list / +table-get` | 列出数据表，或获取单个表详情 | `lark_get_skill(domain="base", section="table-list")`、`lark_get_skill(domain="base", section="table-get")` | `+table-list` 只能串行执行；`+table-get` 适合删除/修改前确认目标 |
| `+table-create / +table-update / +table-delete` | 创建、更新或删除数据表 | `lark_get_skill(domain="base", section="table-create")`、`lark_get_skill(domain="base", section="table-update")`、`lark_get_skill(domain="base", section="table-delete")` | 创建适合一次性建表；更新前先确认目标表；删除时用户已明确目标可直接执行并带 `--yes` |

#### 2.3.2 Field 子模块

普通字段管理走这里；如果字段类型是 `formula` 或 `lookup`，转到下方“公式 / Lookup 模块”。  
子模块索引：`lark_get_skill(domain="base", section="field")`

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+field-list / +field-get` | 列出字段结构，或获取单个字段详情 | `lark_get_skill(domain="base", section="field-list")`、`lark_get_skill(domain="base", section="field-get")` | 写记录、写字段、做分析前常先读 `+field-list`；`+field-list` 只能串行执行；`+field-get` 适合删除/更新前确认目标 |
| `+field-create / +field-update / +field-delete` | 创建、更新或删除普通字段 | `lark_get_skill(domain="base", section="field-create")`、`lark_get_skill(domain="base", section="field-update")`、`lark_get_skill(domain="base", section="field-delete")`、`lark_get_skill(domain="base", section="shortcut-field-properties")` | 写字段前先看字段属性规范；如果涉及类型转换，直接按 `+field-update` 中的字段类型变更规则执行，只在安全白名单内考虑原地转换；如果类型是 `formula / lookup`，先转去读对应 guide；更新或删除时用户已明确目标可直接执行并带 `--yes` |
| `+field-search-options` | 查询字段可选项 | `lark_get_skill(domain="base", section="field-search-options")` | 适合单选/多选等选项型字段 |

#### 2.3.3 Record 子模块

子模块索引：`lark_get_skill(domain="base", section="record")`、`lark_get_skill(domain="base", section="history")`

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+record-search / +record-list / +record-get` | 按关键词检索记录、读取记录明细 / 分页导出，或按 ID 获取一条或多条记录 | `lark_get_skill(domain="base", section="data-analysis-sop")` | 记录读取统一先读 data analysis SOP：已知 `record_id` 用 `+record-get`；明确关键词用 `+record-search`；普通明细用 `+record-list`；明确筛选 / 排序 / Top N 用临时视图投影后 `+record-list --view-id`；统计聚合才分流到 `+data-query`；`+record-get` 支持重复 `--record-id` 或 `--json` 读取多条记录 |
| `+record-upsert / +record-batch-create / +record-batch-update` | 创建、更新或批量写入记录 | `lark_get_skill(domain="base", section="record-upsert")`、`lark_get_skill(domain="base", section="record-batch-create")`、`lark_get_skill(domain="base", section="record-batch-update")`、`lark_get_skill(domain="base", section="cell-value")` | 写前先 `+field-list`；只写存储字段；`+record-batch-update` 为同值更新（同一 patch 应用到多条记录）；批量单次不超过 `200` 条；附件不要走这里 |
| `+record-upload-attachment` | 给已有记录上传一个或多个附件 | 看 `lark_base_record_upload_attachment()` | 附件上传专用链路，不要用 `+record-upsert` / `+record-batch-*` 伪造附件值；不支持 `--name` |
| `+record-download-attachment` | 下载一个或多个 Base 附件到本地 | 看 `lark_base_record_download_attachment()` | Base 附件必须用这个命令下载；用其他下载入口可能失败 |
| `+record-remove-attachment` | 删除附件字段里的一个或多个附件 | 看 `lark_base_record_remove_attachment()` | 删除操作；确认目标后带 `--yes` |
| `+record-delete` | 删除一条或多条记录 | `lark_get_skill(domain="base", section="record-delete")` | 删除多条时重复传 `--record-id` 指定多个记录；用户已明确目标可直接执行并带 `--yes` |
| `+record-history-list` | 查询指定记录的变更历史 | `lark_get_skill(domain="base", section="record-history-list")` | 按 `table-id + record-id` 查询，不支持整表扫描；`+record-history-list` 只能串行执行 |
| `+record-share-link-create` | 为一条或多条记录生成分享链接 | `lark_get_skill(domain="base", section="record-share-link-create")` | 单次最多 100 条；重复 record_id 会自动去重；适合分享单条记录或批量分享场景 |

#### 2.3.4 View 子模块

子模块索引：`lark_get_skill(domain="base", section="view")`

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+view-list / +view-get` | 列出视图，或获取视图详情 | `lark_get_skill(domain="base", section="view-list")`、`lark_get_skill(domain="base", section="view-get")` | `+view-list` 只能串行执行；`+view-get` 适合查看已有视图配置 |
| `+view-create / +view-delete / +view-rename` | 创建、删除或重命名视图 | `lark_get_skill(domain="base", section="view-create")`、`lark_get_skill(domain="base", section="view-delete")`、`lark_get_skill(domain="base", section="view-rename")` | 创建前先确认表和视图类型；删除前先确认目标；用户已明确新名字时可直接重命名 |
| `+view-get-filter / +view-set-filter` | 读取或配置筛选条件 | `lark_get_skill(domain="base", section="view-get-filter")`、`lark_get_skill(domain="base", section="view-set-filter")`、`lark_get_skill(domain="base", section="data-analysis-sop")` | 常与 `+record-list` 组合，用于按视图筛选读取 |
| `+view-get-sort / +view-set-sort` | 读取或配置排序 | `lark_get_skill(domain="base", section="view-get-sort")`、`lark_get_skill(domain="base", section="view-set-sort")` | 字段名必须来自真实结构 |
| `+view-get-group / +view-set-group` | 读取或配置分组 | `lark_get_skill(domain="base", section="view-get-group")`、`lark_get_skill(domain="base", section="view-set-group")` | 字段名必须来自真实结构 |
| `+view-get-visible-fields / +view-set-visible-fields` | 读取或配置视图可见字段 | `lark_get_skill(domain="base", section="view-get-visible-fields")`、`lark_get_skill(domain="base", section="view-set-visible-fields")` | 用于控制视图中的字段顺序与可见性；字段名必须来自真实结构 |
| `+view-get-card / +view-set-card` | 读取或配置卡片视图 | `lark_get_skill(domain="base", section="view-get-card")`、`lark_get_skill(domain="base", section="view-set-card")` | 适合卡片展示场景 |
| `+view-get-timebar / +view-set-timebar` | 读取或配置时间轴视图 | `lark_get_skill(domain="base", section="view-get-timebar")`、`lark_get_skill(domain="base", section="view-set-timebar")` | 适合时间线展示场景 |

### 2.4 公式 / Lookup 模块

只要用户诉求涉及派生指标、条件判断、文本处理、日期差、跨表计算、跨表筛选后取值，都要先判断是否进入本模块。

默认优先考虑 `formula`：适合常规计算、条件判断、文本处理、日期差、跨表聚合，以及需要长期显示在表里的派生结果。  
只有当用户明确要求 `lookup`，或场景天然符合 `from / select / where / aggregate` 这种固定查找建模时，再使用 `lookup`。

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+field-create`（`type=formula`） | 创建公式字段 | `lark_get_skill(domain="base", section="formula-field-guide")`、`lark_get_skill(domain="base", section="field-create")`、`lark_get_skill(domain="base", section="shortcut-field-properties")` | 没读 guide 前不要直接创建 |
| `+field-update`（`type=formula`） | 更新公式字段 | `lark_get_skill(domain="base", section="formula-field-guide")`、`lark_get_skill(domain="base", section="field-update")`、`lark_get_skill(domain="base", section="shortcut-field-properties")` | 先拿当前表结构 |
| `+field-create`（`type=lookup`） | 创建 lookup 字段 | `lark_get_skill(domain="base", section="lookup-field-guide")`、`lark_get_skill(domain="base", section="field-create")`、`lark_get_skill(domain="base", section="shortcut-field-properties")` | 没读 guide 前不要直接创建 |
| `+field-update`（`type=lookup`） | 更新 lookup 字段 | `lark_get_skill(domain="base", section="lookup-field-guide")`、`lark_get_skill(domain="base", section="field-update")`、`lark_get_skill(domain="base", section="shortcut-field-properties")` | 跨表时还要拿目标表结构 |

### 2.5 数据分析模块

用于一次性分析和临时聚合查询。用户要的是“这次算出来的结果”，而不是把结果沉淀成字段时，优先进入本模块。

进入本模块前先确认几件事：

- `+data-query` 只做聚合查询（分组、过滤、排序、聚合计算），不用于列出原始记录或逐条明细。
- 调用者必须是目标多维表格的管理员，拥有目标多维表格的 FA（Full Access / 完全访问权限），否则会返回权限错误。
- `+data-query` 只支持白名单字段类型；`formula`、`lookup`、附件、系统字段、关联等字段不能用于 `dimensions / measures / filters / sort`。

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+data-query` | 做分组统计、SUM / AVG / COUNT / MAX / MIN、条件筛选后的聚合分析 | `lark_get_skill(domain="base", section="data-query")` | 字段名必须精确匹配真实字段名；不要用 `+record-list` / `+record-search` 拉全量再手算；`+data-query` 不返回原始记录；使用前先确认权限和字段类型是否受支持 |

### 2.6 Workflow 模块

这是高约束模块。执行任何 workflow 命令前，都必须先读对应命令文档和 schema。  
模块索引：`lark_get_skill(domain="base", section="workflow")`

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+workflow-list / +workflow-get` | 列出 workflow，或获取完整 workflow 结构 | `lark_get_skill(domain="base", section="workflow-list")`、`lark_get_skill(domain="base", section="workflow-get")`、`lark_get_skill(domain="base", section="workflow-schema")` | `+workflow-list` 只返回摘要且只能串行执行；需要完整结构时用 `+workflow-get` |
| `+workflow-create / +workflow-update` | 创建或更新 workflow | `lark_get_skill(domain="base", section="workflow-create")`、`lark_get_skill(domain="base", section="workflow-update")`、`lark_get_skill(domain="base", section="workflow-schema")` | 先读 schema；禁止凭自然语言猜 `type`；先确认真实表名和字段名 |
| `+workflow-enable / +workflow-disable` | 启用或停用 workflow | `lark_get_skill(domain="base", section="workflow-enable")`、`lark_get_skill(domain="base", section="workflow-disable")`、`lark_get_skill(domain="base", section="workflow-schema")` | 启用或停用前先确认目标 workflow；`workflow_id` 与 `table_id` 需按前缀区分 |

### 2.7 Dashboard 模块

当用户提到“仪表盘、dashboard、数据看板、图表、可视化、block、组件、添加组件、创建图表”等关键词时，进入本模块，并先阅读 `lark_get_skill(domain="base", section="dashboard")`。

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+dashboard-list / +dashboard-get` | 列出仪表盘，或获取仪表盘详情 | `lark_get_skill(domain="base", section="dashboard-list")`、`lark_get_skill(domain="base", section="dashboard-get")`、`lark_get_skill(domain="base", section="dashboard")` | 进入仪表盘语义后先读 guide；`+dashboard-list` 只能串行执行 |
| `+dashboard-create / +dashboard-update / +dashboard-delete` | 创建、更新或删除仪表盘 | `lark_get_skill(domain="base", section="dashboard-create")`、`lark_get_skill(domain="base", section="dashboard-update")`、`lark_get_skill(domain="base", section="dashboard-delete")`、`lark_get_skill(domain="base", section="dashboard")` | 创建前先明确看板目标和展示场景；更新前先读取当前配置；删除前先确认目标 |
| `+dashboard-block-list / +dashboard-block-get` | 列出图表组件，或获取单个 block 详情 | `lark_get_skill(domain="base", section="dashboard-block-list")`、`lark_get_skill(domain="base", section="dashboard-block-get")`、`lark_get_skill(domain="base", section="dashboard")`、`lark_get_skill(domain="base", section="dashboard-block-data-config")` | `+dashboard-block-list` 只能串行执行；查看配置细节时读 block config 文档 |
| `+dashboard-block-create / +dashboard-block-update / +dashboard-block-delete` | 创建、更新或删除图表组件 | `lark_get_skill(domain="base", section="dashboard-block-create")`、`lark_get_skill(domain="base", section="dashboard-block-update")`、`lark_get_skill(domain="base", section="dashboard-block-delete")`、`lark_get_skill(domain="base", section="dashboard")`、`lark_get_skill(domain="base", section="dashboard-block-data-config")` | 涉及 `data_config`、图表类型、filter 时要读 block config 文档；删除前先确认目标 |

### 2.8 表单模块

用于管理表单本体和表单题目。  
模块索引：`lark_get_skill(domain="base", section="form")`、`lark_get_skill(domain="base", section="form-questions")`  
表单问题相关操作依赖 `form-id`；具体获取方式见 `form-list` 和 `form-create` 的 reference。

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+form-list / +form-get` | 列出表单，或获取单个表单 | `lark_get_skill(domain="base", section="form-list")`、`lark_get_skill(domain="base", section="form-get")` | `+form-list` 可用来获取 `form-id`；`+form-get` 适合查看已有表单配置 |
| `+form-detail` | 通过表单分享链接获取表单详情（含题目列表、字段类型、校验规则） | `lark_get_skill(domain="base", section="form-detail")` | 只读；仅需 `--share-token`（从分享链接提取），不需要 base-token/table-id/form-id；返回的 `questions` 可直接用于 `+form-submit` 构造参数 |
| `+form-submit` | 通过表单分享链接填写并提交表单（支持普通字段 + 附件上传） | `lark_get_skill(domain="base", section="form-submit")` | 写入操作；仅支持 share_token 模式；**当 `--json` 包含 attachments 时必须额外提供 `--base-token`**（附件上传到 Base Drive Media 需要）；附件通过 `--json.attachments` 传入本地路径，CLI 自动并行上传 |
| `+form-create / +form-update / +form-delete` | 创建、更新或删除表单 | `lark_get_skill(domain="base", section="form-create")`、`lark_get_skill(domain="base", section="form-update")`、`lark_get_skill(domain="base", section="form-delete")` | 创建后可继续进入表单问题相关操作；更新或删除前先确认目标表单 |
| `+form-questions-list` | 列出表单题目 | `lark_get_skill(domain="base", section="form-questions-list")` | 适合查看已有题目结构 |
| `+form-questions-create / +form-questions-update / +form-questions-delete` | 创建、更新或删除题目 | `lark_get_skill(domain="base", section="form-questions-create")`、`lark_get_skill(domain="base", section="form-questions-update")`、`lark_get_skill(domain="base", section="form-questions-delete")` | 先确认 `form-id`；更新或删除前先确认题目目标 |

### 2.9 权限与角色模块

用于启用高级权限，以及管理 Base 自定义角色。  
涉及 `+advperm-enable / +advperm-disable / +role-*` 时，操作用户必须为 Base 管理员，否则会返回权限错误。

| 命令 | 用途 / 何时使用 | 必读 reference | 路由提醒 |
|------|------------------|----------------|----------|
| `+advperm-enable / +advperm-disable` | 启用或停用高级权限 | `lark_get_skill(domain="base", section="advperm-enable")`、`lark_get_skill(domain="base", section="advperm-disable")` | 管理角色前必须先启用；停用是高风险操作，会使已有自定义角色失效 |
| `+role-list / +role-get` | 列出角色，或获取角色详情 | `lark_get_skill(domain="base", section="role-list")`、`lark_get_skill(domain="base", section="role-get")`、`lark_get_skill(domain="base", section="role-config")` | `+role-list` 只能串行执行；`+role-get` 适合查看完整权限配置 |
| `+role-create / +role-update / +role-delete` | 创建、更新或删除角色 | `lark_get_skill(domain="base", section="role-create")`、`lark_get_skill(domain="base", section="role-update")`、`lark_get_skill(domain="base", section="role-delete")`、`lark_get_skill(domain="base", section="role-config")` | `+role-create` 仅支持 `custom_role`；`+role-update` 采用 Delta Merge，`role_name` 和 `role_type` 即使不改也必须传当前值；`+role-delete` 不可逆 |

## 3. 多维表格通用知识

飞书多维表格英文名是 `Base`，曾用名 `Bitable`；因此旧文档、返回字段、参数名或错误信息里出现 `bitable` 多属历史兼容，不代表应改用另一套命令体系。

### 3.1 字段分类与可写性

| 字段类型 | 含义 | 能否直接作为 `+record-upsert / +record-batch-create / +record-batch-update` 写入目标 | 说明 |
|----------|------|-----------------------------------------------------------|------|
| 存储字段 | 真实存用户输入的数据 | 可以 | 常见如文本、数字、日期、单选、多选、人员、关联 |
| 附件字段 | 存储文件附件 | 不应直接按普通字段写 | 上传附件走 `+record-upload-attachment`；下载附件走 `+record-download-attachment`；删除附件走 `+record-remove-attachment` |
| 地理位置字段 | 存储坐标并由平台解析地址 | 可以 | 写入必须使用 `{lng,lat}`；读取、筛选和转文本等场景使用 `full_address` 字符串；只有公式能访问坐标 |
| 系统字段 | 平台自动维护 | 不可以 | 常见如创建时间、更新时间、创建人、修改人、自动编号 |
| `formula` 字段 | 通过表达式计算 | 不可以 | 只读字段 |
| `lookup` 字段 | 通过跨表规则查找引用 | 不可以 | 只读字段 |

### 3.2 任务选路心智模型

| 用户诉求 | 优先方案 | 不要误走 |
|---------|----------|----------|
| 一次性分析 / 临时统计 | `+data-query` | 不要用 `+record-list` / `+record-search` 拉全量后手算 |
| 要把结果长期显示在表里 | `formula` 字段 | 不要只给一次性手工分析结果 |
| 用户明确要求 lookup，或天然是固定查找配置 | `lookup` 字段 | 不要默认先上 lookup；先判断 formula 是否更合适 |
| 读取原始记录明细 / 关键词检索 / 导出 | `+record-search / +record-list / +record-get` | 不要拿 `+data-query` 当取数命令 |
| 上传附件到记录 | `+record-upload-attachment` | 不要用 `+record-upsert` / `+record-batch-*` 伪造附件值 |
| 下载记录里的附件文件 | `+record-download-attachment --record-id <record_id> --output <dir>`，可加 `--file-token <file_token>` 只下指定附件 | Base 附件必须用这个命令下载；用其他下载入口可能失败 |
| 写入地理位置 | `+record-upsert` / `+record-batch-*` 传 `{lng,lat}` | 不要把纯地址文本当成 CellValue |
| 基于视图做筛选读取 | `+view-set-filter` + `+record-list` | 不要跳过视图筛选直接猜条件 |
| 本地 Excel / CSV / `.base` 导入为 Base | `lark_drive_import()` | 不要误走 `+base-create`、`+table-create` 或 `+record-upsert` |

### 3.3 查询执行契约

涉及查询、统计或判断结论时，先阅读 `lark_get_skill(domain="base", section="data-analysis-sop")`，并遵守以下高优先级规则：

1. `+record-list` 默认页、固定 `--limit` 和本地 `jq` 只能证明已读取范围内的事实，不能直接支撑全局最值、全量计数、Top/Bottom N、异常识别或分组结论。
2. 能由 Base 表达的筛选、排序、投影、聚合、分组和限制，应在 Base 云端查询服务中执行；不要先拉明细到本地上下文再手工筛选排序。
3. `has_more=true` 或等价分页信号表示当前结果不是全量；除非用户只要样例/前 N 条，不能基于该页回答全局问题。
4. 多表查询必须先确认关系字段和连接键；link 单元格里的 `record_id` 是关系键，不是用户可读答案。
5. 最终答案必须能追溯到真实表、真实字段、查询范围、筛选/排序/聚合条件和必要的连接键。

### 3.4 表名、字段名与表达式引用

1. 表名、字段名必须精确匹配真实返回，来源应是 `+table-list / +table-get / +field-list`。
2. 不要凭自然语言猜名称，不要自行改写用户口述中的表名、字段名。
3. `formula / lookup / data-query / workflow` 中出现的名称同样必须精确匹配；表达式引用、where 条件、DSL 字段名、workflow 配置都遵守同一规则。
4. 跨表场景必须额外读取目标表结构，不能只看当前表。

### 3.5 Token 与链接

这是高优先级章节。只要用户输入里出现链接、token，或报错涉及 `baseToken` / `wiki_token` / `obj_token`，都应优先回到这里检查。

| 输入类型 | 正确处理方式 | 说明 |
|---------|--------------|------|
| 直接 Base 链接 `/base/{token}` | 直接提取 token 作为 `--base-token` | 不要把完整 URL 直接作为 `--base-token` |
| Wiki 链接 `/wiki/{token}` | 先用下方 fast path 解析 `data.obj_token` | 不要把 `wiki_token` 直接当 `--base-token`；如果这一步失败，再看 `lark_get_skill(domain="wiki", section="node-get")` |
| URL 中的 `?table={id}` | 先按前缀判断对象类型 | `tbl` 开头表示数据表 `table-id`，可作为 `--table-id`；`blk` 开头表示仪表盘 `dashboard-ID`；`wkf` 开头表示 `workflow-ID`；`ldx` 开头表示内嵌文档，不要一律当成 `--table-id` |
| URL 中的 `?view={id}` | 提取为 `--view-id` | 适合直接定位视图 |

Wiki Base fast path:

```
lark_wiki_node_get(node_token="<wiki_url_or_token>")
```

| `lark_wiki_node_get` 返回的 `data.obj_type` | 后续路线 | 说明 |
|-----------------------------------------------|----------|------|
| `bitable` | 优先走 `lark_base_*` 工具 | 如果 shortcut 不覆盖，再用 `lark_invoke(tool_name="lark_base_<resource>_<method>")`；不要改走 裸 API 调用 |
| `docx` | 转到文档 / Drive 相关 skill | 不继续使用本 skill 的 Base 命令 |
| `sheet` | 转到 Sheets 相关 skill | 不继续使用本 skill 的 Base 命令 |
| `slides` | 转到 Drive 相关 skill | 不继续使用本 skill 的 Base 命令 |
| `mindnote` | 转到 Drive 相关 skill | 不继续使用本 skill 的 Base 命令 |

### 3.6 身份选择与权限降级策略

多维表格通常属于用户的个人或团队资源。MCP server 自动使用用户身份执行所有 Base 操作（authentication is handled automatically by the MCP server）。

如果操作返回权限错误，直接告知用户权限不足，建议用户在飞书开发者后台确认资源访问权限。

## 4. 执行规则

### 4.1 标准执行顺序

1. 先判断任务属于哪个模块，选对命令族。
2. 如果用户给了链接，先解析 token，不要把 wiki token、完整 URL 或其他对象 ID 误当成 `base_token`。
3. 如果是查询类任务，先判断问题范围，阅读 data analysis SOP，再决定使用 `record / view / data-query`。
4. 先拿结构，再写命令，避免猜表名、字段名、表达式引用。
5. 定位到命令后，先读对应 reference，再执行命令。
6. 执行命令，并按返回结果判断下一步。
7. 回复时返回关键结果和后续可继续操作的信息，方便 agent 链式执行下一步。

### 4.2 不可违反规则

1. 先拿结构，再写命令；至少先拿当前表结构，跨表时还要拿目标表结构。
2. 不要猜表名、字段名、表达式引用，一律以真实返回为准。
3. 只使用原子命令；不要回退到旧的聚合式 `+table / +field / +record / +view / +history / +workspace`。
4. 写记录前先读字段结构；先 `+field-list`，再按 `lark_get_skill(domain="base", section="cell-value")` 构造 CellValue。
5. 写字段前先看字段属性规范；先读 `lark-base-shortcut-field-properties.md`，再构造 `+field-create / +field-update` 的 JSON。
6. 只写可写字段；系统字段、附件字段、`formula`、`lookup` 默认不作为普通记录写入目标。
7. 聚合分析与取数分流；统计走 `+data-query`，关键词检索走 `+record-search`，明细走 `+record-list / +record-get`。
8. 筛选查询按视图能力执行；先用 `+view-set-filter` 配置筛选，再结合 `+record-list` 读取。
9. 全局查询不得基于默认分页、小 `--limit` 或未证明全量的本地 `jq` 结果下结论。
10. Base 场景不要改走裸 API，不要切去 裸 API 调用。
11. 统一使用 `--base-token`。
12. workflow 场景先读 schema，不要凭自然语言猜 `type`。
13. dashboard 场景先读 guide；提到图表、看板、block 就先进入 dashboard 模块。
14. formula / lookup 场景先读 guide；没读 guide 前不要直接创建或更新。

### 4.3 并发、分页与批量限制

- `+table-list / +field-list / +record-list / +view-list / +record-history-list / +role-list / +dashboard-list / +dashboard-block-list / +workflow-list` 禁止并发调用，只能串行执行。
- `+record-list` 分页时，`--limit` 最大 `200`；先拉首批并检查 `has_more`，只有用户明确需要更多数据时再继续翻页。
- 批量写入时，单批不超过 `200` 条。
- 连续写入同一表时，必须串行写入，批次间延迟 `0.5–1` 秒。

### 4.4 确认与回复规则

- 视图重命名时，用户已明确“把哪个视图改成什么名字”时，`+view-rename` 直接执行即可。
- 更新字段或删除记录 / 字段 / 表时，如果用户已经明确目标，`+field-update / +record-delete / +field-delete / +table-delete` 可直接执行，并带 `--yes`。
- 删除目标仍有歧义时，先用 `+record-get / +field-get / +table-get` 或相应 list 命令确认。
- `+base-create / +base-copy` 成功后，回复中必须主动返回新 Base 的标识信息；若结果带可访问链接，也应一并返回。
- 若 Base 由 bot 身份创建或复制，shortcut 会自动尝试为当前 CLI 用户补授 `full_access`，并在输出中返回 `permission_grant`；agent 不需要再手动编排单独授权。owner 转移必须单独确认，禁止擅自执行。

## 5. 常见错误与恢复

| 错误 / 现象 | 含义 | 恢复动作 |
|-------------|------|----------|
| `1254064` | 日期格式错误 | 传 `YYYY-MM-DD HH:mm:ss` 字符串，不要写相对时间 |
| `1254068` | 超链接格式错误 | `"https://example.com"` 或 `"[文本](https://example.com)"` |
| `1254066` | 人员字段错误 | `[{ "id": "ou_xxx" }]` |
| `1254045` | 字段名不存在 | 检查字段名（含空格、大小写） |
| `1254015` | 字段值类型不匹配 | 先 `+field-list`，再按类型构造 |
| `param baseToken is invalid` / `base_token invalid` | 把 wiki token、workspace token 或其他 token 当成了 `base_token` | 如果输入来自 `/wiki/...`，先用 `lark_wiki_node_get()` 取真实 `data.obj_token`；当 `data.obj_type=bitable` 时，用 `data.obj_token` 作为 `--base-token` 重试，不要改走 `bitable/v1` |
| `not found` 且用户给的是 wiki 链接 | 常见于把 wiki token 当成 base token | 优先回退检查 wiki 解析，而不是改走 `bitable/v1` |
| formula / lookup 创建失败 | 指南未读或结构不合法 | 先读 `formula-field-guide.md` / `lookup-field-guide.md`，再按 guide 重建请求 |
| `ignored_fields` / `READONLY` | 只读字段被当成可写字段，常见于系统字段、formula、lookup | 移除只读字段，只写存储字段；计算结果交给 formula / lookup / 系统字段自动产出 |
| `1254104` | 批量超 200 条 | 分批调用 |
| `1254291` | 并发写冲突 | 串行写入 + 批次间延迟 |
| `91403` | 无权限访问该 Base | **不要重试**。按 `lark-shared` 权限不足处理流程引导用户解决权限问题 |
