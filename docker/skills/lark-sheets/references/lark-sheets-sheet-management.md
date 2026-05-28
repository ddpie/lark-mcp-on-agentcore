# Sheets Sheet Management

这份 reference 汇总工作表级操作：

- `lark_sheets_create_sheet`
- `lark_sheets_copy_sheet`
- `lark_sheets_delete_sheet`
- `lark_sheets_update_sheet`

其中 `lark_sheets_create_sheet` / `lark_sheets_copy_sheet` / `lark_sheets_delete_sheet` 底层封装官方"操作工作表（operate-sheets）"接口；`lark_sheets_update_sheet` 封装"更新工作表属性"接口。

<a id="create-sheet"></a>
## `lark_sheets_create_sheet`

```
# 在表格末尾或服务端默认位置创建工作表
lark_sheets_create_sheet(spreadsheet_token="shtxxxxxxxx", title="明细")

# 指定插入位置（0-based）
lark_sheets_create_sheet(url="https://example.larksuite.com/sheets/shtxxxxxxxx", title="汇总", index="0")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `title` | 否 | 工作表标题，最长 100 字符，不能包含 `/ \ ? * [ ] :` |
| `index` | 否 | 工作表位置（从 0 开始） |

输出：

- `spreadsheet_token`
- `sheet.sheet_id`
- `sheet.title`
- `sheet.index`

<a id="copy-sheet"></a>
## `lark_sheets_copy_sheet`

```
# 按默认位置复制
lark_sheets_copy_sheet(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>")

# 指定副本名称和位置
lark_sheets_copy_sheet(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", title="销售副本", index="2")
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 源工作表 ID |
| `title` | 否 | 新工作表标题，最长 100 字符，不能包含 `/ \ ? * [ ] :` |
| `index` | 否 | 新工作表位置（从 0 开始） |

说明：

- 传 `index` 时，会先复制，再追加一次位置更新，把副本移动到目标索引

输出：

- `spreadsheet_token`
- `sheet.sheet_id`
- `sheet.title`
- `sheet.index`

<a id="delete-sheet"></a>
## `lark_sheets_delete_sheet`

> [!CAUTION]
> 这是**高风险删除操作**。需要传 `_confirm=true` 确认执行。

```
lark_sheets_delete_sheet(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", _confirm=true)
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 要删除的工作表 ID |

输出：

- `deleted`
- `spreadsheet_token`
- `sheet_id`

<a id="update-sheet"></a>
## `lark_sheets_update_sheet`

用于更新工作表标题、位置、隐藏状态、冻结行列和保护设置。

```
# 改名 + 调整冻结
lark_sheets_update_sheet(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", title="汇总表", frozen_row_count="2", frozen_col_count="1")

# 隐藏工作表
lark_sheets_update_sheet(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", hidden="true")

# 开启保护并授权额外编辑人
lark_sheets_update_sheet(spreadsheet_token="shtxxxxxxxx", sheet_id="<sheetId>", lock="LOCK", lock_info="仅财务维护", user_id_type="open_id", user_ids='["ou_xxx","ou_yyy"]')
```

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `sheet_id` | 是 | 要更新的工作表 ID |
| `title` | 否 | 新标题，最长 100 字符，不能包含 `/ \ ? * [ ] :` |
| `index` | 否 | 新位置（从 0 开始） |
| `hidden` | 否 | `true` 隐藏，`false` 取消隐藏 |
| `frozen_row_count` | 否 | 冻结行数，`0` 表示取消冻结 |
| `frozen_col_count` | 否 | 冻结列数，`0` 表示取消冻结 |
| `lock` | 否 | 保护模式：`LOCK` / `UNLOCK` |
| `lock_info` | 否 | 保护备注；要求 `lock="LOCK"` |
| `user_id_type` | 否 | `user_ids` 的 ID 类型：`open_id` / `union_id` / `lark_id` / `user_id` |
| `user_ids` | 否 | 额外可编辑用户 ID 的 JSON 数组；要求 `lock="LOCK"` |

输出：

- `spreadsheet_token`
- `sheet.sheet_id`
- `sheet.title`
- `sheet.hidden`
- `sheet.grid_properties.frozen_row_count`
- `sheet.grid_properties.frozen_column_count`
- `sheet.protect`

## 参考

- lark_get_skill(domain="sheets", section="spreadsheet-management") — 先获取 `sheet_id`
- lark_get_skill(domain="sheets", section="row-column-management") — 需要改行列结构时用这组工具
