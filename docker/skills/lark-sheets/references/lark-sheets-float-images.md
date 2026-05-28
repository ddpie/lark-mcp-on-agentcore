# Sheets Float Images

这份 reference 汇总浮动图片相关能力：

- `lark_sheets_media_upload`
- `lark_sheets_create_float_image`
- `lark_sheets_update_float_image`
- `lark_sheets_get_float_image`
- `lark_sheets_list_float_images`
- `lark_sheets_delete_float_image`

<a id="media-upload"></a>
## `lark_sheets_media_upload`

把本地图片上传到指定电子表格的素材空间，返回 `file_token`，供 `lark_sheets_create_float_image` 使用。

```
lark_sheets_media_upload(url="https://example.larksuite.com/sheets/shtxxxxxxxx", file="./image.png")
```

说明：

- 内部调用 `drive/v1/medias/upload_all`
- `>20MB` 自动分片上传
- `file` 只能是当前工作目录下的相对路径

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 否 | 电子表格 URL（与 `spreadsheet_token` 二选一） |
| `spreadsheet_token` | 否 | 表格 token |
| `file` | 是 | 本地图片路径，必须是相对路径 |

输出：`file_token`、`file_name`、`size`、`spreadsheet_token`

<a id="create-float-image"></a>
## `lark_sheets_create_float_image`

```
lark_sheets_create_float_image(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", float_image_token="boxcnXXXX", range="<sheetId>!A1:A1", width="200", height="150")
```

关键规则：

- `float_image_token` 必须来自 `lark_sheets_media_upload`
- `range` 必须锚定单个单元格
- `width` / `height` 必须 `>=20`
- `offset_x` / `offset_y` 必须 `>=0`

输出：`float_image`

<a id="update-float-image"></a>
## `lark_sheets_update_float_image`

```
lark_sheets_update_float_image(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", float_image_id="fi12345678", width="400", height="300", offset_y="20")
```

至少需要传一个更新字段：`range` / `width` / `height` / `offset_x` / `offset_y`

输出：更新后的 `float_image`

<a id="get-float-image"></a>
## `lark_sheets_get_float_image`

```
lark_sheets_get_float_image(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", float_image_id="fi12345678")
```

输出：`float_image`

<a id="list-float-images"></a>
## `lark_sheets_list_float_images`

```
lark_sheets_list_float_images(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>")
```

输出：`items[]`

<a id="delete-float-image"></a>
## `lark_sheets_delete_float_image`

```
lark_sheets_delete_float_image(url="https://example.larksuite.com/sheets/shtxxxxxxxx", sheet_id="<sheetId>", float_image_id="fi12345678")
```

输出：`code`、`msg`

## 读取图片内容

上述读接口只返回元数据，不返回图片字节。要读取图片内容，用 `float_image_token` 调：

```
lark_docs_media_preview(token="<float_image_token>", output="./image.png")
```

## 参考

- lark_get_skill(domain="sheets", section="cell-images") — 写入到单元格的图片
- lark_get_skill(domain="sheets", section="spreadsheet-management") — 先获取 `sheet_id`
