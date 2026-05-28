# Sheets Cell Data

这份 reference 汇总单元格数据操作：

- `lark_sheets_read`
- `lark_sheets_write`
- `lark_sheets_append`
- `lark_sheets_find`
- `lark_sheets_replace`

<a id="read"></a>
## `lark_sheets_read`

内置能力：

- 支持 `url` / `spreadsheet_token` 二选一（URL 支持 wiki）
- 若已传 `sheet_id`，`range` 可写 `A1:D10` 或 `C2`
- 默认最多返回 200 行

```
lark_sheets_read(url="https://example.larksuite.com/sheets/shtxxxxxxxx", range="<sheetId>!A1:H20")

lark_sheets_read(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", range="C2")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 否 | `<sheetId>!A1:D10`、`A1:D10` / `C2` 或 `<sheetId>` |
| `sheet_id` | 否 | 工作表 ID |
| `value_render_option` | 否 | `ToString` / `FormattedValue` / `Formula` / `UnformattedValue` |

输出：

- `range`
- `values`
- `truncated`
- `total_rows`

<a id="write"></a>
## `lark_sheets_write`

用于覆盖写入一个矩形区域。

```
lark_sheets_write(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A1:B2", values='[["name","age"],["alice",18]]')

lark_sheets_write(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", range="C2", values='[["hello"]]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 否 | 写入范围；可用相对范围或 `<sheetId>` |
| `sheet_id` | 否 | 工作表 ID |
| `values` | 是 | 二维数组 JSON |

输出：

- `updated_range`
- `updated_rows`
- `updated_columns`
- `updated_cells`
- `revision`

<a id="append"></a>
## `lark_sheets_append`

用于向工作表末尾追加行。

```
lark_sheets_append(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A1", values='[["华东一仓","2026-03",125000,98000,168000,"41.7%"]]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 否 | 追加范围：支持 `<sheetId>`、完整范围、相对范围 |
| `sheet_id` | 否 | 工作表 ID |
| `values` | 是 | 二维数组 JSON |

输出：

- `table_range`
- `updated_range`
- `updated_rows`
- `updated_columns`
- `updated_cells`
- `revision`

<a id="find"></a>
## `lark_sheets_find`

只在一个已知 spreadsheet 内查找单元格内容，不是云空间（云盘/云存储）搜索。

```
lark_sheets_find(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", find="张三", range="A1:H200")

lark_sheets_find(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", find="仓库管理营收报表", ignore_case=true)
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `find` | 是 | 查找内容 |
| `range` | 否 | 范围；不填则搜索整个工作表 |
| `ignore_case` | 否 | 不区分大小写 |
| `match_entire_cell` | 否 | 完全匹配单元格 |
| `search_by_regex` | 否 | 使用正则 |
| `include_formulas` | 否 | 搜索公式 |

输出：

- `matched_cells`
- `matched_formula_cells`
- `rows_count`

<a id="replace"></a>
## `lark_sheets_replace`

在指定范围内查找并替换单元格内容。

```
lark_sheets_replace(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", find="hello", replacement="world")

lark_sheets_replace(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", find="\\d{4}-\\d{2}-\\d{2}", replacement="DATE", search_by_regex=true)
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `find` | 是 | 搜索文本 |
| `replacement` | 是 | 替换文本 |
| `range` | 否 | 搜索范围，不传则搜索整个工作表 |
| `match_case` | 否 | 区分大小写 |
| `match_entire_cell` | 否 | 匹配整个单元格 |
| `search_by_regex` | 否 | 使用正则 |
| `include_formulas` | 否 | 在公式中搜索 |

输出：

- `replace_result.matched_cells`
- `replace_result.matched_formula_cells`
- `replace_result.rows_count`

## 参考

- lark_get_skill(domain="sheets", section="spreadsheet-management") — 先获取 `sheet_id`
- lark_get_skill(domain="sheets", section="dropdown") — 写入 `multipleValue` 前先设置下拉列表
- lark_get_skill(domain="sheets", section="formula") — 公式写入规则
