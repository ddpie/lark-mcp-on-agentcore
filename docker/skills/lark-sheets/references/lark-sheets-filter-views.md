# Sheets Filter Views

这份 reference 汇总筛选视图和筛选条件：

- `lark_sheets_create_filter_view`
- `lark_sheets_update_filter_view`
- `lark_sheets_list_filter_views`
- `lark_sheets_get_filter_view`
- `lark_sheets_delete_filter_view`
- `lark_sheets_create_filter_view_condition`
- `lark_sheets_update_filter_view_condition`
- `lark_sheets_list_filter_view_conditions`
- `lark_sheets_get_filter_view_condition`
- `lark_sheets_delete_filter_view_condition`

<a id="create-filter-view"></a>
## `lark_sheets_create_filter_view`

在工作表中创建筛选视图，每个工作表最多 150 个。

```
lark_sheets_create_filter_view(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", range="<sheetId>!A1:H14")

lark_sheets_create_filter_view(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", range="<sheetId>!A1:H14", filter_view_name="我的筛选")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `range` | 是 | 筛选范围 |
| `filter_view_name` | 否 | 显示名称 |
| `filter_view_id` | 否 | 自定义 10 位字母数字 ID |

输出：`filter_view`

<a id="update-filter-view"></a>
## `lark_sheets_update_filter_view`

```
lark_sheets_update_filter_view(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>", range="<sheetId>!A1:J20")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `filter_view_id` | 是 | 筛选视图 ID |
| `range` | 否 | 新范围 |
| `filter_view_name` | 否 | 新显示名称 |

<a id="list-filter-views"></a>
## `lark_sheets_list_filter_views`

```
lark_sheets_list_filter_views(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>")
```

输出：`items[]`（`filter_view_id`、`filter_view_name`、`range`）

<a id="get-filter-view"></a>
## `lark_sheets_get_filter_view`

```
lark_sheets_get_filter_view(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>")
```

输出：`filter_view`

<a id="delete-filter-view"></a>
## `lark_sheets_delete_filter_view`

```
lark_sheets_delete_filter_view(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `filter_view_id` | 是 | 筛选视图 ID |

<a id="create-filter-view-condition"></a>
## `lark_sheets_create_filter_view_condition`

为筛选视图的指定列创建筛选条件。

```
# 数值筛选：E 列 < 6
lark_sheets_create_filter_view_condition(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>", condition_id="E", filter_type="number", compare_type="less", expected='["6"]')

# 文本筛选：G 列以 a 开头
lark_sheets_create_filter_view_condition(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>", condition_id="G", filter_type="text", compare_type="beginsWith", expected='["a"]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `filter_view_id` | 是 | 筛选视图 ID |
| `condition_id` | 是 | 列字母，如 `E` |
| `filter_type` | 是 | `hiddenValue` / `number` / `text` / `color` |
| `compare_type` | 否 | 比较运算符 |
| `expected` | 是 | 筛选值 JSON 数组 |

输出：`condition`

<a id="update-filter-view-condition"></a>
## `lark_sheets_update_filter_view_condition`

```
lark_sheets_update_filter_view_condition(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>", condition_id="E", filter_type="number", compare_type="between", expected='["2","10"]')
```

参数与创建条件相同，但 `filter_type` / `compare_type` / `expected` 可按需部分更新。

<a id="list-filter-view-conditions"></a>
## `lark_sheets_list_filter_view_conditions`

```
lark_sheets_list_filter_view_conditions(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>")
```

输出：`items[]`

<a id="get-filter-view-condition"></a>
## `lark_sheets_get_filter_view_condition`

```
lark_sheets_get_filter_view_condition(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>", condition_id="E")
```

输出：`condition`

<a id="delete-filter-view-condition"></a>
## `lark_sheets_delete_filter_view_condition`

```
lark_sheets_delete_filter_view_condition(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", filter_view_id="<fvId>", condition_id="E")
```

## 参考

- lark_get_skill(domain="sheets", section="dropdown") — 需要下拉值配合筛选时
- lark_get_skill(domain="sheets", section="cell-data") — 只查数据时用 `lark_sheets_find`
