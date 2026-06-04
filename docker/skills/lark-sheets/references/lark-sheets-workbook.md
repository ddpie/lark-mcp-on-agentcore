# Lark Sheet Workbook

## Sheet 结构变更保守化（编辑类任务必做）

`lark_sheets_sheet_{create|delete|rename|move|copy|hide|unhide|set-tab-color}` 会改变原表的物理结构，是高副作用动作。执行前必须遵守：

1. **删除 / 重命名 / 隐藏 / 移动原 Sheet 需用户明示**：除非用户明示要这些操作，**禁止**擅自对**已存在**的 Sheet 执行 delete / rename / hide / move。新建 Sheet 是允许的（用于承载中间结果或透视表 / 图表对象），但应优先在原表右侧加列；只有当中间结果数量较大或会与原数据混淆时，才新建空白 Sheet（同 R1）。
2. **Sheet 级操作前先列清单**：调用 `lark_sheets_sheet_{create|delete|rename|move|copy|hide|unhide|set-tab-color}` 之前，必须先调用 `lark_sheets_workbook_info`，把"当前所有 Sheet 名 + 可见性 + 行列数"列出来，再决定是否操作。禁止跳过列清单直接 create / delete / rename。
3. **删除 / 重命名前向用户确认**：删除是不可逆的，重命名会让其他公式 / 透视表 / 图表的数据源失效——执行前必须在回复里确认"将删除 / 改名 X，影响 Y 个引用"。

## 使用场景

读写。管理工作簿结构。本 reference 覆盖 11 个 shortcut：

| 操作需求 | 使用工具 | 说明 |
|---------|---------|------|
| 查看工作簿结构 | `lark_sheets_workbook_info` | 获取子表列表、名称、行列数、冻结位置等元数据 |
| 变更工作簿结构 | `lark_sheets_sheet_{create|delete|rename|move|copy|hide|unhide|set-tab-color}` | 新建/删除/移动/重命名/复制/隐藏子表、修改标签颜色 |

注意：

- 如果用户请求包含多个动作，例如"先重命名，再新建工作表"，请按顺序发起多次调用，覆盖全部动作
- `create` 时若用户指定了工作表名称，应显式传入 `sheet_name`；不要省略后依赖默认命名
- 若 `lark_sheets_workbook_info` 返回包含 `warning_message`，说明部分 `sheet_id` 已失效（被删除/改名或输入错误），应停止复用这些 id，重新不带 `sheet_ids` 全量获取结构后再继续操作

**常见配置错误（必须注意）**：
- **获取结构是第一步**：任何表格操作前必须先调用 `lark_sheets_workbook_info`，不要跳过直接操作。返回的行列数、子表列表是后续所有操作的基础
- **sheet_id 不要写错**：从 `lark_sheets_workbook_info` 返回值中精确获取 `sheet_id`，不要手动拼写或从 URL 中猜测
- **优先使用 `sheet_id`**：虽然飞书表格不允许子表重名，但 `sheet_id` 是稳定标识符，跨多轮操作时不会因用户中途重命名而失效

## Shortcuts

| Shortcut | Risk | 分组 |
| --- | --- | --- |
| `lark_sheets_workbook_info` | read | 工作簿 |
| `lark_sheets_sheet_create` | write | 工作簿 |
| `lark_sheets_sheet_delete` | high-risk-write | 工作簿 |
| `lark_sheets_sheet_rename` | write | 工作簿 |
| `lark_sheets_sheet_move` | write | 工作簿 |
| `lark_sheets_sheet_copy` | write | 工作簿 |
| `lark_sheets_sheet_hide` | write | 工作簿 |
| `lark_sheets_sheet_unhide` | write | 工作簿 |
| `lark_sheets_sheet_set_tab_color` | write | 工作簿 |
| `lark_sheets_workbook_create` | write | 工作簿 |
| `lark_sheets_workbook_export` | read | 工作簿 |

## Flags

### `lark_sheets_workbook_info`

_公共：URL/token（无 sheet 定位）_

_仅含公共 / 系统 flag。_

### `lark_sheets_sheet_create`

_公共：URL/token（无 sheet 定位）_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | required | 新工作表名称 |
| `index` | int | optional | 插入位置；省略时附加到末尾 |
| `row_count` | int | optional | 初始行数（默认 200，上限 50000） |
| `col_count` | int | optional | 初始列数（默认 20，上限 200） |

### `lark_sheets_sheet_delete`

_公共四件套 · high-risk-write（需 _confirm=true）_

_仅含公共 / 系统 flag。_

### `lark_sheets_sheet_rename`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | required | 新名称 |

### `lark_sheets_sheet_move`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `index` | int | required | 目标位置（0-based） |
| `source_index` | int | optional | 源位置（0-based）；可选，未传时由 CLI runtime 根据 `sheet_id` / `sheet_name` 当前在工作簿中的 index 自动派生 |

### `lark_sheets_sheet_copy`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | optional | 副本名称；省略时由服务端生成 |
| `index` | int | optional | 副本插入位置（0-based）；省略时附加到末尾 |

### `lark_sheets_sheet_hide`

_公共四件套_

_仅含公共 / 系统 flag。_

### `lark_sheets_sheet_unhide`

_公共四件套_

_仅含公共 / 系统 flag。_

### `lark_sheets_sheet_set_tab_color`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `color` | string | required | Hex 色值如 `#FF0000`，传空 `""` 清除 |

### `lark_sheets_workbook_create`



| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | required | 新 spreadsheet 标题 |
| `folder_token` | string | optional | 目标文件夹 token；省略时放在云空间根目录 |
| `headers` | string + File + Stdin（简单 JSON） | optional | 表头行 JSON 数组：`["列A","列B"]` |
| `values` | string + File + Stdin（简单 JSON） | optional | 初始数据 JSON 二维数组：`[["alice",95]]` |

### `lark_sheets_workbook_export`

_公共：URL/token（无 sheet 定位）_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `file_extension` | string | optional | 导出文件格式；`csv` 模式必须配 `sheet_id`（可选值：`xlsx` / `csv`）（默认 `xlsx`） |
| `sheet_id` | string | optional | 仅 csv 模式必填：指定要导出哪张 sheet 为 CSV。这是 `lark_sheets_workbook_export` 专有 flag，与公共四件套的 sheet 定位无关（本 shortcut 不接受公共 sheet 定位） |
| `output_path` | string | optional | 本地保存路径；省略时只触发导出不下载 |

## Examples

公共四件套：所有 shortcut 顶部排列 `url` / `spreadsheet_token` / `sheet_id` / `sheet_name`（XOR）。`lark_sheets_workbook_info` 只用前两者；`lark_sheets_sheet_*` 系列对单个工作表操作，需 `sheet_id` 或 `sheet_name`。

### `lark_sheets_workbook_info`

输出契约：返回 `sheets[]`，每个含 `sheet_id` / `title`（工作表显示名；旧 payload 用 `sheet_name`，读取时优先取 `title`、缺失再回退 `sheet_name`）/ `row_count` / `column_count` / `index` / `is_hidden`，以及计数字段 `merged_cells_count` / `chart_count` / `pivot_table_count` / `float_image_count`（无 `frozen_*` 字段，冻结信息请用 `lark_sheets_sheet_info` 读取）。是操作飞书表格的第一步——任何后续 sheet 级动作都需要先拿这里的 sheet_id。

### `lark_sheets_sheet_create`

示例：

```
lark_sheets_sheet_create(url="https://example.feishu.cn/sheets/shtXXX", title="汇总", index="0")
```

### `lark_sheets_sheet_delete`

> ⚠️ 工作表删除不可逆；先 `dry_run` 看输出 sheet_id + title 确认是要删的那张。

### `lark_sheets_sheet_rename`

```
lark_sheets_sheet_rename(url="...", sheet_id="$SID", title="汇总")
```

### `lark_sheets_sheet_move`

standalone 路径在缺 `source_index` / 只给 `sheet_name` 时会自动发起一次 `lark_sheets_workbook_info` 读把它们解出来。

> ⚠️ **在 `lark_sheets_batch_update` 内调用 `lark_sheets_sheet_move`**：必须同时显式传 `sheet_id`、`source_index` 和 `index`（目标位置）。batch 中途无法发起结构查询，且 `index` 不显式给会静默落到默认位置 0，所以 batch translator 强制要求三者都显式。

### `lark_sheets_sheet_copy`

```
# title 省略时由服务端生成副本名
lark_sheets_sheet_copy(url="...", sheet_id="$SID", title="副本")
```

### `lark_sheets_sheet_hide` / `lark_sheets_sheet_unhide`

```
lark_sheets_sheet_hide(url="...", sheet_id="$SID")
lark_sheets_sheet_unhide(url="...", sheet_id="$SID")
```

### `lark_sheets_sheet_set_tab_color`

```
# Hex 色值；传空字符串 "" 清除标签色
lark_sheets_sheet_set_tab_color(url="...", sheet_id="$SID", color="#FF0000")
```

### Validate / DryRun / Execute 约束

- `Validate`：XOR 公共四件套；`lark_sheets_sheet_create` 校验 `title` 非空、`row_count` ≤ 50000、`col_count` ≤ 200；`lark_sheets_sheet_delete` 必须 `yes` 或 `dry_run`。
- `DryRun`：`lark_sheets_sheet_*` 写操作输出"将要 PATCH 的 sheet metadata"；`sheet_name` 在 dry-run 输出里生成为 `<resolve:Sheet1>` 占位符，不实际解析为 sheet-id。
- `Execute`：写操作不自动回读；如需确认目标 sheet 的新状态，自行调用 `lark_sheets_workbook_info`。
