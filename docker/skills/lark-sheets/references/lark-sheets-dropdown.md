# Sheets Dropdown

这份 reference 汇总下拉列表配置：

- `lark_sheets_set_dropdown`
- `lark_sheets_update_dropdown`
- `lark_sheets_get_dropdown`
- `lark_sheets_delete_dropdown`

> **关键规则：** 使用 `multipleValue` 写入前，必须先设置下拉列表；否则值会被当成纯文本。

<a id="set-dropdown"></a>
## `lark_sheets_set_dropdown`

```
lark_sheets_set_dropdown(url="https://example.larksuite.com/sheets/shtxxxxxxxx", range="<sheetId>!A2:A100", condition_values='["选项1", "选项2", "选项3"]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 是 | 范围（如 `<sheetId>!A2:A100`） |
| `condition_values` | 是 | 下拉选项 JSON 数组 |
| `multiple` | 否 | 是否多选 |
| `highlight` | 否 | 是否着色 |
| `colors` | 否 | 颜色 JSON 数组 |

输出：`code`、`msg`

<a id="update-dropdown"></a>
## `lark_sheets_update_dropdown`

```
lark_sheets_update_dropdown(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", ranges='["<sheetId>!A1:A100"]', condition_values='["选项A", "选项B"]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 工作表 ID |
| `ranges` | 是 | 范围 JSON 数组 |
| `condition_values` | 是 | 选项 JSON 数组 |
| `multiple` | 否 | 是否多选 |
| `highlight` | 否 | 是否着色 |
| `colors` | 否 | 颜色 JSON 数组 |

输出：`spreadsheetToken`、`sheetId`、`dataValidation`

<a id="get-dropdown"></a>
## `lark_sheets_get_dropdown`

```
lark_sheets_get_dropdown(spreadsheet_token="shtxxxxxxxx", range="<sheetId>!A2:A100")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `range` | 是 | 查询范围 |

输出：

- `dataValidations[].conditionValues`
- `dataValidations[].ranges`
- `dataValidations[].options.multipleValues`
- `dataValidations[].options.highlightValidData`
- `dataValidations[].options.colorValueMap`

<a id="delete-dropdown"></a>
## `lark_sheets_delete_dropdown`

```
lark_sheets_delete_dropdown(spreadsheet_token="shtxxxxxxxx", ranges='["<sheetId>!A2:A100", "<sheetId>!C1:C50"]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `ranges` | 是 | 范围 JSON 数组 |

输出：

- `rangeResults[].range`
- `rangeResults[].success`
- `rangeResults[].updatedCells`

## 典型流程

```
# 1. 配置下拉
lark_sheets_set_dropdown(url="<url>", range="<sheetId>!J2:J100", condition_values='["选项1","选项2"]', multiple=true)

# 2. 再写入 multipleValue
lark_sheets_write(url="<url>", sheet_id="<sheetId>", range="J2", values='[[{"type":"multipleValue","values":["选项1","选项2"]}]]')
```

## 参考

- lark_get_skill(domain="sheets", section="cell-data") — 写入普通单元格数据
