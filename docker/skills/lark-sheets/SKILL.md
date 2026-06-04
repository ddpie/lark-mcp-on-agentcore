---
name: lark-sheets
description: "飞书电子表格：创建和操作电子表格。支持创建表格、管理工作表与行列结构（增删/合并/调整尺寸/隐藏/冻结）、读写单元格（值/公式/样式/批注/单元格图片）、查找替换、多操作原子批量更新，以及图表、透视表、条件格式、筛选器、迷你图、浮动图片等对象的创建与维护。当用户需要创建电子表格、管理工作表、批量读写或编辑数据、统计汇总与可视化、表格美化、公式计算（含 Excel 公式迁移）等任务时使用。若用户是想按名称或关键词搜索云空间（云盘/云存储）里的表格文件，请改用 lark-drive 的 lark_drive_search 先定位资源。当用户给出 doubao.com 的 /sheets/ URL/token 时，也应直接使用本 skill，不要因为域名不是飞书而回退到 WebFetch；路由依据是 URL 路径模式和 token，而不是域名。仅针对飞书在线电子表格，不适用于本地 Excel 文件。"
---

# sheets

（认证由 MCP server 自动处理。）

## 术语约定

下列词在本 skill 各文档中可能交替出现，但**指同一对象**；解析用户口语时按此映射，不要当成不同概念：

| 标准用语 | 同义 / 口语（均指同一对象） | 说明 |
| --- | --- | --- |
| 工作表（sheet） | 子表、tab、标签页 | spreadsheet 内的单张表；`sheet_id` 是其稳定标识 |
| 电子表格（spreadsheet） | 工作簿、表格 | 顶层容器；由 `url` 或 `spreadsheet_token` 定位 |
| reference_id | id | **表内对象**的稳定标识，即各对象主键参数接受的值（见下表）。⚠️ 与 float-image 的 `image_uri`（图片上传句柄）不是一回事，后者不属于 reference_id |

每类对象用各自的主键参数定位（命名不统一，按此表对照，不要凭直觉拼）：

| 对象 | 主键参数 | 对象 | 主键参数 |
| --- | --- | --- | --- |
| 工作表 sheet | `sheet_id` | 条件格式规则 | `rule_id` |
| 图表 chart | `chart_id` | 筛选视图 | `view_id` |
| 透视表 pivot | `pivot_table_id` | 迷你图（按组） | `group_id` |
| 浮动图片 | `float_image_id` | | |

## 场景 → 工具速查（拿不准工具名先查这里，别按直觉拼）

把高频意图映射到**真实存在**的工具 / 参数。agent 常从 Excel / Google Sheets / 飞书 OpenAPI 误迁移工具名或参数，先对照本表，避免一次必然失败的试错。完整工具见各工具参考。

| 你要做的事 | ✅ 正确写法 | ❌ 不存在 |
| --- | --- | --- |
| 读数据（纯值 / CSV） | `lark_sheets_csv_get`（范围用 `range`） | — |
| 读值 + 公式 / 样式 / 批注 | `lark_sheets_cells_get(include="value,formula,style,comment,data_validation")` | `with_styles`、`with_merges`、`include_merged_cells` |
| 写纯值（整块 CSV 平铺） | `lark_sheets_csv_put`（定位用 `start_cell`，单个左上角锚点格；也接受 `range` 别名，区间自动取左上角） | — |
| 写值 / 公式 / 样式 | `lark_sheets_cells_set`（定位用 `range`） | — |
| 查找单元格 | `lark_sheets_cells_search`（关键字用 `find`） | `lark_sheets_cells_find`、`lark_sheets_find`、`query` |
| 查找并替换 | `lark_sheets_cells_replace` | — |
| 看子表结构（合并 / 行高列宽 / 冻结 / 隐藏） | `lark_sheets_sheet_info` | `lark_sheets_sheet_get`、`lark_sheets_structure_get` |
| 看工作簿 / 子表清单 | `lark_sheets_workbook_info` | — |
| 导出 xlsx / 单表 csv | `lark_sheets_workbook_export` | — |
| 清除内容 / 格式 | `lark_sheets_cells_clear`（范围维度用 `scope`，取值 content / formats / all） | `type` |
| 批量清除多区域 | `lark_sheets_cells_batch_clear`（`scope`） | `target` |
| 调整列宽 / 行高 | `lark_sheets_cols_resize` / `lark_sheets_rows_resize`（行、列是两个独立工具） | `dimension`（无此参数） |
| 分组汇总 / 透视 | `lark_sheets_pivot_create`（默认不传落点参数 → 自动新建子表，零覆盖） | 用 SUMIF / 本地脚本拼一张假透视表 |

> ⚠️ **定位参数**：`lark_sheets_cells_get` / `lark_sheets_cells_set` / `lark_sheets_csv_get` 用 `range`；`lark_sheets_csv_put` 规范用 `start_cell`（单个左上角锚点格），也接受 `range` 别名（区间自动取左上角），二者择一即可。
> ⚠️ **读取附加信息**一律走 `lark_sheets_cells_get(include=…)`，**没有** `with_styles` 这类参数；**看合并单元格**用 `lark_sheets_sheet_info` 的 `merged_cells`，不要在 `lark_sheets_cells_get` 里找 merge 参数。

## References

本 skill 的 reference 分两组：先读**通用方法与规范**（横切所有任务的工作流、铁律、样式、公式规则，不含具体工具），它们规定了"怎么做对"；再按操作对象进入**工具参考**查具体工具与调用细节。编辑类任务务必先过一遍通用方法与规范，其中的铁律对所有工具参考一律生效。

### 通用方法与规范（先读，横切所有任务，不含具体工具）

| Reference | 描述 |
| --- | --- |
| 飞书表格核心操作：分析、编辑与可视化 — `lark_get_skill(domain="sheets", section="core-operations")` | 飞书表格核心操作工作流。当用户需要对已有的飞书表格进行查看、分析、编辑或可视化时使用。适用场景：数据查询与统计、公式计算、表格美化、创建图表/透视表、筛选排序、批量修改数据、调整表格结构等。即使用户没有明确说"飞书表格"，只要操作对象是已有的在线表格，都应触发此工作流。不适用于本地 Excel 文件操作。 |
| 飞书表格样式与配色规范 — `lark_get_skill(domain="sheets", section="visual-standards")` | 飞书表格样式与配色规范：表头/数据区/汇总行的颜色、字号、对齐、边框等取值标准，以及新增汇总行、追加行列继承原表风格、已有区域美化等典型场景的决策流程与样式要点。工具调用参数细节请参考对应的 write-cells / range-operations / batch-update。条件格式（高亮、标红、数据条、色阶）请使用 conditional-format。仅针对飞书表格，不适用于本地 Excel 文件。 |
| 飞书表格公式生成规则 — `lark_get_skill(domain="sheets", section="formula-translation")` | Excel 公式到飞书表格公式的迁移与生成规则。核心目标不是保留 Excel 原语法，而是按飞书表格可执行规则重写公式，并在结果上尽量对齐 Excel。当用户要求把 Excel 公式改写成飞书表格公式，或需要生成飞书公式（尤其涉及 ARRAYFORMULA、原生数组函数、INDEX/OFFSET、MAP/LAMBDA、日期差、多层范围结果与二次展开）时使用。仅针对飞书在线表格，不适用于本地 Excel 文件执行。 |

### 按对象的工具参考（含工具）

| Reference | 描述 |
| --- | --- |
| Lark Sheet Workbook — `lark_get_skill(domain="sheets", section="workbook")` | 管理飞书表格的工作簿结构（子表列表及元数据）。当用户提到"看看这个表格有什么"、"表格结构"、"有哪些 sheet"、"新建一个 sheet"、"删除这个工作表"、"重命名"、"复制一份"、"移动到前面"时使用。仅针对飞书表格。 |
| Lark Sheet Sheet Structure — `lark_get_skill(domain="sheets", section="sheet-structure")` | 管理飞书表格的子表结构与布局。适用场景：查看行高、列宽、隐藏行列、合并单元格等布局信息，以及"插入一行"、"删除这列"、"隐藏行"、"冻结表头"、行列分组（大纲折叠/展开）等操作。行列大纲仅在用户明确提到"行分组"、"列分组"、"大纲"、"outline"时才触发，"按XXX分组"等数据分组场景请使用 pivot-table。如需在表尾追加数据，应先通过此 skill 插入行，再通过 write-cells 写入。仅针对飞书表格。 |
| Lark Sheet Read Data — `lark_get_skill(domain="sheets", section="read-data")` | 读取飞书表格中的单元格数据。当用户需要"看看数据"、"分析数据"、"统计/汇总"时使用；也适用于需要查看公式、样式、批注等详细信息的场景。仅针对飞书表格。 |
| Lark Sheet Search & Replace — `lark_get_skill(domain="sheets", section="search-replace")` | 在飞书表格中搜索和替换文本，支持限定范围、大小写匹配、精确匹配、正则表达式。当用户需要"查找"、"搜索"、"定位"某个值，或"替换"、"批量修改文本"、"把 A 改成 B"时使用。不要用于理解表格结构（应读取数据）、不要用于数据分析（应读取数据后计算）、不要把用户操作动作中的关键词（如"汇总金额""统计数量"）当作搜索词。仅针对飞书表格。 |
| Lark Sheet Write Cells — `lark_get_skill(domain="sheets", section="write-cells")` | 向飞书表格的指定区域批量写入值、公式、样式、批注或单元格图片。适用场景：填写数据、设置公式、修改格式、添加批注、嵌入单元格图片（如需操作浮动图片，请使用 float-image）；若只需把一块 CSV 纯值批量铺到表格上（不带公式/样式），直接使用 `lark_sheets_csv_put` 更短更快。追加数据需先通过 sheet-structure 插入行列。仅针对飞书表格。 |
| Lark Sheet Range Operations — `lark_get_skill(domain="sheets", section="range-operations")` | 对飞书表格中指定区域执行结构性操作（不涉及写入单元格数据值）。适用场景：清除内容或格式（"清空"、"删除内容"、"去掉格式"）、合并/取消合并单元格、调整行高列宽（"加宽列"、"自适应列宽"）、移动/复制/填充/排序数据（"移动数据"、"复制到"、"自动填充"、"按某列排序"）。写入单元格数据请使用 write-cells。仅针对飞书表格。 |
| Lark Sheet Batch Update — `lark_get_skill(domain="sheets", section="batch-update")` | 将多个飞书表格写入操作合并为一次批量执行，按顺序依次完成。适合需要连续执行多个写入操作的场景（如先修改结构再写入数据）。仅针对飞书表格。 |
| Lark Sheet Chart — `lark_get_skill(domain="sheets", section="chart")` | 管理飞书表格中的图表（柱形图、折线图、饼图、条形图、面积图、散点图、组合图、雷达图等）。当用户需要创建图表、修改图表样式或数据源、查看已有图表配置、删除图表时使用。也适用于用户提到"数据可视化"、"画个图"、"趋势分析"、"对比图"、"占比分析"、"做个图表"等数据可视化相关场景。仅针对飞书表格。 |
| Lark Sheet Pivot Table — `lark_get_skill(domain="sheets", section="pivot-table")` | 管理飞书表格中的数据透视表。当用户需要创建透视表、修改透视表的行列字段/聚合方式/筛选条件、查看已有透视表配置、删除透视表时使用。也适用于用户提到"分组汇总"、"交叉分析"、"按XXX统计"、"按字段分组"、"再分下组"、"多维分析"、"数据透视"等场景。仅针对飞书表格。 |
| Lark Sheet Conditional Format — `lark_get_skill(domain="sheets", section="conditional-format")` | 管理飞书表格中的条件格式规则（重复值高亮、单元格值比较、数据条、色阶、排名、自定义公式等）。当用户需要创建条件格式、修改已有规则的范围或样式、查看当前条件格式配置、删除规则时使用。也适用于用户提到"高亮"、"标红"、"颜色标记"、"数据条"、"色阶"、"条件样式"等场景。仅针对飞书表格。 |
| Lark Sheet Filter — `lark_get_skill(domain="sheets", section="filter")` | 管理飞书表格中的筛选器（filter）。当用户需要筛选数据（按文本/数值/颜色/日期条件过滤行）、查看已有筛选配置、修改或删除筛选器时使用。也适用于"只看"、"筛选出"、"仅保留符合条件的"等场景。仅针对飞书表格。 |
| Lark Sheet Filter View — `lark_get_skill(domain="sheets", section="filter-view")` | 管理飞书表格中的筛选视图（filter view）。当用户需要"建一个 XX 视图"、"保存这个筛选状态"、"切换不同筛选"、维护一个 sheet 上多份独立筛选配置时使用。视图与筛选器（filter）相互独立，可在同一 sheet 共存；视图的隐藏行仅在用户进入该视图时本地生效，不影响其他协作者。仅针对飞书表格。 |
| Lark Sheet Sparkline — `lark_get_skill(domain="sheets", section="sparkline")` | 管理飞书表格中的迷你图（折线迷你图、柱形迷你图、胜负迷你图）。当用户需要在单元格内嵌入小型图表来展示数据趋势时使用。也适用于"趋势线"、"单元格内图表"、"迷你图"等场景。注意：不等同于被禁用的 SPARKLINE() 公式函数。仅针对飞书表格。 |
| Lark Sheet Float Image — `lark_get_skill(domain="sheets", section="float-image")` | 管理飞书表格中的浮动图片。当用户需要在表格中插入浮动图片、调整图片位置和大小、查看已有浮动图片、删除图片时使用。也适用于"插入图片"、"添加 logo"、"放一张图"等场景。注意：如果用户需要将图片嵌入到某个单元格内部（单元格图片），请阅读 write-cells。仅针对飞书表格。 |

## 公共参数速查

各 reference 的每个工具下用一行徽章标注该工具支持的公共参数，例如：

- `_公共四件套_` — URL/token + sheet 定位（两组各**必给一个**，详见下方「公共参数」）
- `_公共：URL/token（无 sheet 定位）_` — 只接 URL/token，常见于 `lark_sheets_batch_update` 等不强制 sheet 定位的工具

### 公共参数（定位资源）

**公共四件套** = `url` / `spreadsheet_token` / `sheet_id` / `sheet_name`，分成两组 XOR，**每组都必须给且只能给一个**（XOR = 二选一必填，不是"可选"）：

1. **spreadsheet 定位（必填）**：`url` 与 `spreadsheet_token` 二选一，**必须给其中之一**。两个都不给 → 校验报错 `specify at least one of --url or --spreadsheet-token`；两个都给 → 互斥冲突。
   - **`url` 只解析 `/sheets/` 与 `/spreadsheets/` 两种链接**（从路径里抽出 token；也可以直接把裸 token 传给 `spreadsheet_token`）。其它形态的链接不会被解析成表格 token。
   - ⚠️ **`/wiki/` 知识库链接不能直接当表格定位用**：wiki 链接背后可能是电子表格，也可能是文档 / 多维表格等其它类型，`url` **不会**自动把 wiki token 解析成 spreadsheet token，直接传会失败。必须先把它解析成真实文档 token —— `lark_wiki_node_get(node_token="<wiki 链接或 token>")`，确认返回的 `obj_type` 为 `sheet` 后，取其 `obj_token` 作为 `spreadsheet_token` 传入（解析细节见 `lark_get_skill(domain="wiki")`）。
   - **例外**：`lark_sheets_workbook_create` 是新建一个还不存在的表格，**不接受任何 spreadsheet / sheet 定位参数**（只有 `title` / `folder_token` / `headers` / `values`）。
2. **sheet 定位（公共四件套工具必填）**：`sheet_id` 与 `sheet_name` 二选一，**必须给其中之一**。两个都不给 → 校验报错 `specify at least one of --sheet-id or --sheet-name`。
   - ⚠️ **不确定 sheet 名时禁止直接猜 `Sheet1`**：除非用户对话明确说出 sheet 名 / id，或上下文（之前的工具调用 / URL 锚点 `?sheet=xxx`）已经出现过具体值，否则**第一步先调 `lark_sheets_workbook_info(url="...")`**（或 `spreadsheet_token`）拿 `sheets[].sheet_id` / `sheets[].title` 列表再选。中文环境下子表常叫"数据" / "Sheet"（无数字）/ "工作表 1" / 业务名，猜 `Sheet1` 大概率撞 `sheet not found`，比先查多耗一次失败调用 + 重试。
   - ⚠️ **`range` 里的 `Sheet1!` 前缀不能替代 sheet 定位**：即使写了 `range="Sheet1!A1:B2"`，仍**必须**额外传 `sheet_id` 或 `sheet_name`，否则照样报上面的错。
   - **例外**：徽章标为 `_公共：URL/token（无 sheet 定位）…_` 的工具（如 `lark_sheets_workbook_info` / `lark_sheets_workbook_export` / `lark_sheets_batch_update` / `lark_sheets_dropdown_update`|`lark_sheets_dropdown_delete` / `lark_sheets_cells_batch_set_style` / `lark_sheets_cells_batch_clear` / `lark_sheets_sheet_create`）**不接受也不需要** sheet 定位，只给一组 spreadsheet 定位即可。`lark_sheets_pivot_create` 用 `target_sheet_id` / `target_sheet_name`（XOR，可都不传，落点细节见 `lark_get_skill(domain="sheets", section="pivot-table")`）。

| 参数 | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `url` | string | 二选一必填（与 `spreadsheet_token`） | spreadsheet URL |
| `spreadsheet_token` | string | 二选一必填（与 `url`） | spreadsheet token |
| `sheet_id` | string | 二选一必填（与 `sheet_name`；仅公共四件套工具） | 工作表 reference_id |
| `sheet_name` | string | 二选一必填（与 `sheet_id`；仅公共四件套工具） | 工作表名称 |

**统一调用范式**（公共四件套工具的所有示例都遵循此形状，两组定位缺一不可）：

```
lark_sheets_<tool>(<workbook 定位>, <sheet 定位>, <其它参数>)
#   workbook 定位：url="..."        或 spreadsheet_token="..."           （二选一，必给）
#   sheet 定位：    sheet_id="$SID"  或 sheet_name="<真实表名>"            （二选一，必给；占位符不要原样填）
# 例：lark_sheets_csv_get(url="https://.../sheets/shtXXX", sheet_name="<真实表名>", range="A1:F30")
# 注意：真实表名不要直接填 "Sheet1"——大多数表的子表不叫这个；先 lark_sheets_workbook_info 拿 sheets[].title 再代入。
```

### 高风险确认

部分写工具属于 `high-risk-write`（如 `lark_sheets_sheet_delete` / `lark_sheets_dim_delete` / `lark_sheets_cells_clear` / `lark_sheets_batch_update` / `lark_sheets_cells_batch_clear` / `lark_sheets_dropdown_delete` 及各对象的 `*_delete`）。这类工具首次调用会被 MCP server 拒绝并给出确认指引，需再带 `_confirm=true` 重新调用以执行。

### 复合 JSON 参数

写复合 JSON 参数（`cells` / `properties` / `operations` / `border_styles` / `sort_keys` / `options` 等）时，如果对结构不确定，先用 `lark_discover(query="sheets.<tool>")` 把工具 schema 读出来再构造 payload，比靠 reference 的速查表更精确，也避免因为字段拼写或缺失被服务端拒绝。reference 的 `## Schemas` 段只给一层结构，深层只能靠 `lark_discover` 或 `## Examples` 的真实示例。

### 参数内容类型与输出约定（术语速记）

- 参数表里 JSON 类入参标三类：**复合 JSON** = 深层嵌套对象（用 `lark_discover` 取完整结构）；**简单 JSON** = 一维 / 二维标量数组（如 `["sheet1!A1:B2",...]` / `[["alice",95]]`，结构简单）；**非 JSON 文本** = 原样文本（如 CSV）。
- **envelope**：所有工具返回统一外层结构 `{ok, identity, data, ...}`。正文里 `envelope.data` 指业务数据层（如 `lark_sheets_csv_get` 的 `annotated_csv`）；写操作不会自动回读，如需校验请自行调用对应的 `*_list` / `*_get` / `lark_sheets_cells_get`。

## 复合 JSON / 大入参

复合 JSON 参数（`cells` / `properties` / `operations` 等）作为 JSON 对象传入即可（MCP client 负责序列化）。payload 较大、含换行 / 引号等特殊字符时也直接放进参数对象，无需关心命令行转义。
