# Sheets Cell Style and Merge

这份 reference 汇总单元格样式和合并相关操作：

- `lark_sheets_set_style`
- `lark_sheets_batch_set_style`
- `lark_sheets_merge_cells`
- `lark_sheets_unmerge_cells`

<a id="set-style"></a>
## `lark_sheets_set_style`

对指定范围设置字体、颜色、对齐、边框等样式。

```
lark_sheets_set_style(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A1:C3", style='{"font":{"bold":true},"backColor":"#ff0000"}')

lark_sheets_set_style(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A1:Z100", style='{"clean":true}')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 是 | 单元格范围 |
| `sheet_id` | 否 | 工作表 ID（用于相对范围） |
| `style` | 是 | 样式 JSON 对象 |

常用 `style` 字段：

- `font.bold`
- `font.italic`
- `font.font_size`
- `textDecoration`
- `formatter`
- `hAlign`
- `vAlign`
- `foreColor`
- `backColor`
- `borderType`
- `borderColor`
- `clean`

输出：`updates`（updatedRange / updatedRows / updatedColumns / updatedCells / revision）

<a id="batch-set-style"></a>
## `lark_sheets_batch_set_style`

对多个范围批量设置不同样式。

```
lark_sheets_batch_set_style(spreadsheet_token="shtxxxxxxxx", data='[{"ranges":["<sheetId>!A1:C3"],"style":{"font":{"bold":true},"backColor":"#21d11f"}},{"ranges":["<sheetId>!D1:F3"],"style":{"foreColor":"#ff0000"}}]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `data` | 是 | JSON 数组，每项包含 `ranges` 和 `style` |

输出：

- `totalUpdatedRows`
- `totalUpdatedColumns`
- `totalUpdatedCells`
- `revision`
- `responses[]`

<a id="merge-cells"></a>
## `lark_sheets_merge_cells`

支持三种模式：

- `MERGE_ALL`
- `MERGE_ROWS`
- `MERGE_COLUMNS`

```
lark_sheets_merge_cells(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A1:B2", merge_type="MERGE_ALL")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 是 | 单元格范围 |
| `sheet_id` | 否 | 工作表 ID（用于相对范围） |
| `merge_type` | 是 | `MERGE_ALL` / `MERGE_ROWS` / `MERGE_COLUMNS` |

输出：`spreadsheetToken`

<a id="unmerge-cells"></a>
## `lark_sheets_unmerge_cells`

用于拆分合并单元格。

```
lark_sheets_unmerge_cells(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A1:B2")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 是 | 单元格范围 |
| `sheet_id` | 否 | 工作表 ID（用于相对范围） |

输出：`spreadsheetToken`

## 参考

- lark_get_skill(domain="sheets", section="cell-data") — 数据读写
- lark_get_skill(domain="sheets", section="cell-images") — 写入单元格图片
