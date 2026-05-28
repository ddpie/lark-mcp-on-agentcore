# Dashboard（仪表盘/数据看板）模块指引

Dashboard 是 Base 中的数据可视化看板，可以把表格数据变成**组件**（图表、指标卡等）进行展示。

## 核心概念

- **Dashboard（仪表盘）**：容器，包含多个组件
- **Block（组件）**：仪表盘中的单个可视化元素（柱状图、折线图、饼图、指标卡等）
- **data_config**：组件的数据源配置（表名、字段、分组等）

## 能力速览

| 你想做什么 | 用这些命令 | 关键文档 |
|------|-----------|---------|
| 创建/删除/改名称 | `+dashboard-create/delete/update` | 本页下方「仪表盘管理」 |
| 在仪表盘里添加组件 | `+dashboard-block-create` | 先读 `lark_get_skill(domain="base", section="dashboard-block-create")`，再读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` |
| 修改组件 | `+dashboard-block-update` | 先读 `lark_get_skill(domain="base", section="dashboard-block-update")`，再读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` |
| 查看仪表盘有哪些组件 | `+dashboard-get` 或 `+dashboard-block-list` | 本页下方「查看仪表盘」 |
| 智能重排组件布局 | `+dashboard-arrange` | `lark_get_skill(domain="base", section="dashboard-arrange")` |

## 典型场景工作流

### 场景 1：从 0 到 1 创建仪表盘

示例：搭建一个销售数据分析仪表盘

```
# 第 1 步：创建空白仪表盘
lark_base_dashboard_create(base_token="xxx", name="销售数据分析")
# 记录返回的 dashboard_id

# 第 2 步：获取数据源信息
lark_base_table_list(base_token="xxx")
lark_base_field_list(base_token="xxx", table_id="tbl_xxx")

# 第 3 步：规划应该创建哪些组件（根据用户需求确定组件类型和数量）
# 例如：总销售额（指标卡）、月度趋势（折线图）、品类占比（饼图）

# 第 4 步：顺序创建每个组件（必须串行执行，不能并发）
# 重要：创建组件前，先阅读 `lark_get_skill(domain="base", section="dashboard-block-create")` 了解命令参数
# 再阅读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` 了解 data_config 结构、组件类型和 filter 规则

# 第 1 个组件
lark_base_dashboard_block_create(data_config='{"table_name":"订单表","series":[{"field_name":"金额","rollup":"SUM"}]}', base_token="xxx", dashboard_id="blk_xxx", name="总销售额", type="statistics")

# 第 2 个组件（等上一个完成后再执行）
lark_base_dashboard_block_create(data_config='{"table_name":"订单表","series":[{"field_name":"金额","rollup":"SUM"}],"group_by":[{"field_name":"月份","mode":"integrated"}]}', base_token="xxx", dashboard_id="blk_xxx", name="月度趋势", type="line")

# 继续创建其他组件...

# 第 5 步：组件创建完成后，使用 arrange 命令智能重排布局（可选但推荐）
# 默认布局可能不够美观，arrange 会根据组件数量和类型自动优化布局
lark_base_dashboard_arrange(base_token="xxx", dashboard_id="blk_xxx")
```

### 场景 2：在已有仪表盘上添加新组件

```
# 第 1 步：列出仪表盘，定位到当前仪表盘
lark_base_dashboard_list(base_token="xxx")
# 获取目标 dashboard_id

# 第 2 步：根据用户诉求规划组件类型和数据源
# 建议先查看当前仪表盘已有组件，避免重复创建，或作为参考
lark_base_dashboard_get(base_token="xxx", dashboard_id="blk_xxx")

# 第 3 步：获取数据源信息
lark_base_table_list(base_token="xxx")
lark_base_field_list(base_token="xxx", table_id="tbl_xxx")

# 第 4 步：顺序创建每个新组件（必须串行执行，不能并发）
# 重要：先阅读 `lark_get_skill(domain="base", section="dashboard-block-create")` 了解命令参数
# 再阅读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` 了解 data_config 结构
lark_base_dashboard_block_create(data_config='{...}', base_token="xxx", dashboard_id="blk_xxx", name="新组件名", type="column")
```

### 场景 3：编辑已有组件

> [!IMPORTANT]
> `+dashboard-block-update` **不能修改组件的 `type`**（图表类型），只能更新 `name` 和 `data_config`。
> 如需更换组件类型，必须先删除再重新创建。

```
# 第 1 步：列出仪表盘，定位到当前仪表盘
lark_base_dashboard_list(base_token="xxx")

# 第 2 步：列出组件，获取到目标组件
lark_base_dashboard_block_list(base_token="xxx", dashboard_id="blk_xxx")
# 获取目标 block_id
# 提示：查看已有组件可作为参考，或检查是否重复创建相似组件

# 第 3 步：获取组件当前详情
lark_base_dashboard_block_get(base_token="xxx", dashboard_id="blk_xxx", block_id="chtxxxxxxxx")

# 第 4 步：根据用户编辑诉求准备更新
# 如果编辑诉求涉及数据源变更，需要先获取数据源信息
lark_base_table_list(base_token="xxx")
lark_base_field_list(base_token="xxx", table_id="tbl_xxx")

# 第 5 步：执行更新
# 重要：先阅读 `lark_get_skill(domain="base", section="dashboard-block-update")` 了解命令参数
# 再阅读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` 了解 data_config 更新规则
lark_base_dashboard_block_update(data_config='{...}', base_token="xxx", dashboard_id="blk_xxx", block_id="chtxxxxxxxx")
```

### 场景 4：重排仪表盘布局

当用户明确要求对已有仪表盘进行布局重排或美化时使用。

> [!CAUTION]
> - 排列结果是**服务端智能推荐**，不一定完全符合用户预期
> - 无法指定具体位置（如"第一排放 A，第二排放 B"），排列逻辑是**自适应**的
> - **不建议**在已有仪表盘上自动调用，除非用户明确要求

```
# 第 1 步：列出仪表盘，定位到目标仪表盘
lark_base_dashboard_list(base_token="xxx")

# 第 2 步：执行智能重排
lark_base_dashboard_arrange(base_token="xxx", dashboard_id="blk_xxx")
```

### 场景 5：读取仪表盘或组件现状

**选择查询方式：**
- 想看仪表盘整体结构（含主题、所有组件名称和类型）→ 用 **方式 A**
- 只想快速查看有哪些组件 → 用 **方式 B**
- 想看某个组件的详细 data_config 配置 → 用 **方式 C**

```
# 第 1 步：列出仪表盘，定位到当前仪表盘
lark_base_dashboard_list(base_token="xxx")

# 第 2 步：根据用户诉求查看详情

# 方式 A：查看仪表盘整体情况（包含所有组件列表）
lark_base_dashboard_get(base_token="xxx", dashboard_id="blk_xxx")

# 方式 B：列出所有组件
lark_base_dashboard_block_list(base_token="xxx", dashboard_id="blk_xxx")

# 方式 C：查看某个组件的详细配置
lark_base_dashboard_block_get(base_token="xxx", dashboard_id="blk_xxx", block_id="chtxxxxxxxx")

# 最后：把获取到的现状信息整理好告诉用户
```

## 组件类型选择

组件 `type` 决定展示形式：

| 用户想看什么 | 选什么 type | 说明 |
|-------------|------------|------|
| 数据趋势（时间变化） | line | 折线图组件 |
| 类别比较（谁高谁低） | column | 柱状图组件 |
| 占比分布（各部分比例） | pie | 饼图组件 |
| 单个关键指标 | statistics | 指标卡组件 |
| 富文本说明/标题/注释 | text | 文本组件（支持 Markdown） |

详细组件类型和 data_config 完整规则：`lark_get_skill(domain="base", section="dashboard-block-data-config")`

## 常见问题

**Q: 创建组件的命令和 data_config 怎么写？**
A:
1. 先读 `lark_get_skill(domain="base", section="dashboard-block-create")` 了解 `--name`、`--type`、`--data-config` 等参数
2. 再读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` 了解：
   - 全部组件类型的可复制模板
   - filter 筛选条件格式
   - 字段类型与操作符对应表

**Q: 为什么组件创建失败了？**
A: 常见原因：
- `table_name` 用了 table_id 而不是表名（必须用表名称，如「订单表」）
- `series` 和 `count_all` 同时存在（必须二选一，互斥）
- 字段名拼写错误（必须用 `+field-list` 获取的真实字段名，禁止猜测）
- 组件创建并发执行（必须串行，等上一个完成再执行下一个）

**Q: 可以一次创建多个组件吗？**
A: 不可以，必须串行执行。等上一个 `+dashboard-block-create` 完成后再执行下一个。

**Q: 组件的 `type` 创建后能改吗？**
A: 不能。`+dashboard-block-update` 只能修改 `name` 和 `data_config`，不能修改 `type`。

**Q: 更新组件的命令和 data_config 怎么写？**
A:
1. 先读 `lark_get_skill(domain="base", section="dashboard-block-update")` 了解更新参数
2. 再读 `lark_get_skill(domain="base", section="dashboard-block-data-config")` 了解 data_config 结构

**data_config 更新策略（顶层 key merge）**：
- 只传入需要修改的顶层字段（如 `series`、`filter`）
- 未传的顶层字段（如 `group_by`）自动保留原值
- 但每个传入的字段内部是**全量替换**（如传新 `filter` 会完整覆盖旧 `filter`）

**Q: 查看已有组件有什么用？**
A: 在「添加新组件」或「编辑组件」前查看已有组件可以：
- 了解当前仪表盘已有哪些可视化
- 避免重复创建相似的组件
- 参考已有组件的 data_config 结构作为模板

## 命令详细文档

| CLI 命令 | 说明 | 详细文档 |
|----------|------|----------|
| `+dashboard-list` | 列出所有仪表盘 | `lark_get_skill(domain="base", section="dashboard-list")` |
| `+dashboard-get` | 获取仪表盘详情（含所有组件）| `lark_get_skill(domain="base", section="dashboard-get")` |
| `+dashboard-create` | 创建仪表盘 | `lark_get_skill(domain="base", section="dashboard-create")` |
| `+dashboard-update` | 修改仪表盘 | `lark_get_skill(domain="base", section="dashboard-update")` |
| `+dashboard-delete` | 删除仪表盘 | `lark_get_skill(domain="base", section="dashboard-delete")` |
| `+dashboard-arrange` | 智能重排布局 | `lark_get_skill(domain="base", section="dashboard-arrange")` |
| `+dashboard-block-list` | 列出组件 | `lark_get_skill(domain="base", section="dashboard-block-list")` |
| `+dashboard-block-get` | 获取单个组件详情 | `lark_get_skill(domain="base", section="dashboard-block-get")` |
| `+dashboard-block-create` | 创建组件 | `lark_get_skill(domain="base", section="dashboard-block-create")` |
| `+dashboard-block-update` | 更新组件 | `lark_get_skill(domain="base", section="dashboard-block-update")` |
| `+dashboard-block-delete` | 删除组件 | `lark_get_skill(domain="base", section="dashboard-block-delete")` |
