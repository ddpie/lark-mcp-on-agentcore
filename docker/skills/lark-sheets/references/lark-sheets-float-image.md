# Lark Sheet Float Image

> **单元格图片 vs 浮动图片**：飞书表格有两种图片类型，请根据需求选择正确的工具：
> - **单元格图片**：图片嵌入在单元格内部，随单元格移动，属于单元格内容的一部分。→ 使用 `lark_sheets_cells_set`，在 `rich_text` 中设置 `type: "embed-image"`（见 `lark_get_skill(domain="sheets", section="write-cells")`）。
> - **浮动图片**（本 Skill）：图片悬浮在单元格上方，可自由指定位置、大小和层级，不属于任何单元格的内容。→ 使用本 Skill 的 `lark_sheets_float_image_{create|update|delete}`。

## 真对象硬约束

当用户要求"插入图片 / 添加 logo / 放一张图"时，**必须**通过 `lark_sheets_float_image_{create|update|delete}`（浮动图片）或 `lark_sheets_cells_set` 的 `embed-image`（单元格图片）创建真实的图片对象。**禁止**只在文本回复中给出图片链接 / 描述图片内容代替插入。判断标准：交付后 `lark_sheets_float_image_list` 或单元格 `rich_text` 必须能读到该图片对象。

## 使用场景

读写**浮动图片**对象（悬浮在单元格上方的图片，不属于单元格内容）。本 reference 覆盖 4 个 shortcut：

| 操作需求 | 使用工具 | 说明 |
|---------|---------|------|
| 查看已有浮动图片 | `lark_sheets_float_image_list` | 获取浮动图片的位置、大小和层级配置 |
| 创建/更新/删除浮动图片 | `lark_sheets_float_image_{create|update|delete}` | 对浮动图片执行写入操作 |

典型工作流：先读取现有浮动图片了解配置 → 执行创建/更新/删除 → **必须再次读取验证结果**。

**常见配置错误（必须注意）**：
- **单元格图片 vs 浮动图片选择错误**：如果用户希望图片嵌入单元格内部（随单元格移动），应使用 `lark_sheets_cells_set` 的 `rich_text` + `embed-image`，而非本 Skill
- **图片位置参数要精确**：锚点单元格的行列索引和偏移量决定了图片位置，设置不当会导致图片遮挡数据
- **创建后必须验证**：调用 `lark_sheets_float_image_list` 确认图片位置和大小正确

图片来源有三种方式，`lark_sheets_float_image_create` 上三者 **XOR、必给其一**（`image` / `image_token` / `image_uri`）：

- **`image="<本地路径>"`（首选，最省事）**：直接给本地图片文件路径（PNG/JPEG/GIF/BMP/HEIC 等）。CLI 会自动把它以 `parent_type=sheet_image` 上传，拿到 file_token 后创建浮动图，**不用你手动上传 / 取 token**。路径规则同其它本地文件 flag：必须是当前工作目录内的相对路径（绝对路径会被 Validate 拒，`dry_run` 也会拦）。
- `image_token`：复用**已存在**的图片 file_token。常见来源：① `lark_sheets_float_image_list` 返回的 `image_token`（适合"换皮不换位置"复用同一张图）；② `lark_sheets_cells_set_image` 成功返回里的 `file_token`（它也是 `sheet_image` 上传句柄）。适合"同一张图复用到多处"，省去重复上传。
- `image_uri`：图片 reference_id（image URI），由系统自动转 file_token。

> ⚠️ **`image` 仅 `lark_sheets_float_image_create` 支持**。`lark_sheets_float_image_update` 换图仍只接受 `image_token` / `image_uri`，而且**图片源是 update 唯一可省的部分**——三者全不传则保留原图。但 `image_name` / `position_row` / `position_col` / `size_width` / `size_height` 在 update 时和 create 一样**必填**（`manage_float_image` 工具强制要求这套核心字段，且 `lark_sheets_float_image_list` 不回传 `image_name` 供 CLI 回填）。要在 update 里换一张本地新图，先用 `lark_sheets_cells_set_image` 上传到任意临时单元格、从返回取 `file_token`，再把它传给 update 的 `image_token`。

## Shortcuts

| Shortcut | Risk | 分组 |
| --- | --- | --- |
| `lark_sheets_float_image_list` | read | 对象 |
| `lark_sheets_float_image_create` | write | 对象 |
| `lark_sheets_float_image_update` | write | 对象 |
| `lark_sheets_float_image_delete` | high-risk-write | 对象 |

## Flags

### `lark_sheets_float_image_list`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `float_image_id` | string | optional | 按 id 过滤；省略时列工作表全部 |

### `lark_sheets_float_image_create`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `image_name` | string | required | 图片名称，含扩展名（如 `logo.png`） |
| `image_token` | string | xor | 图片 file_token（与 `image_uri` 二选一）。常见来源：`lark_sheets_float_image_list` 返回的 `image_token` |
| `image_uri` | string | xor | 图片 reference_id（与 `image_token` 二选一）；图片上传链路返回的 reference_id |
| `position_row` | int | required | 图片左上角所在行（0-based） |
| `position_col` | string | required | 图片左上角所在列（列字母，如 `A` / `B`） |
| `size_width` | int | required | 图片宽度（像素） |
| `size_height` | int | required | 图片高度（像素） |
| `offset_row` | int | optional | 在 `position_row` 基础上的行内偏移（像素） |
| `offset_col` | int | optional | 在 `position_col` 基础上的列内偏移（像素） |
| `z_index` | int | optional | 图片 Z 轴层级，控制重叠顺序 |
| `image` | string | xor | 本地图片路径（PNG/JPEG 等）；自动上传为 sheet_image 并用返回的 file_token，省去手动拿 token（与 `image_token` / `image_uri` 三选一） |

### `lark_sheets_float_image_update`

_公共四件套_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `float_image_id` | string | required | 目标图片 id |
| `image_name` | string | required | 图片名称，含扩展名（如 `logo.png`） |
| `image_token` | string | xor | 图片 file_token（与 `image_uri` 二选一）。常见来源：`lark_sheets_float_image_list` 返回的 `image_token` |
| `image_uri` | string | xor | 图片 reference_id（与 `image_token` 二选一）；图片上传链路返回的 reference_id |
| `position_row` | int | required | 图片左上角所在行（0-based） |
| `position_col` | string | required | 图片左上角所在列（列字母，如 `A` / `B`） |
| `size_width` | int | required | 图片宽度（像素） |
| `size_height` | int | required | 图片高度（像素） |
| `offset_row` | int | optional | 在 `position_row` 基础上的行内偏移（像素） |
| `offset_col` | int | optional | 在 `position_col` 基础上的列内偏移（像素） |
| `z_index` | int | optional | 图片 Z 轴层级，控制重叠顺序 |

### `lark_sheets_float_image_delete`

_公共四件套 · high-risk-write（需 _confirm=true）_

| Flag | Type | 必填 | 说明 |
| --- | --- | --- | --- |
| `float_image_id` | string | required | 目标图片 id |

## Examples

公共四件套：所有 shortcut 顶部排列 `url` / `spreadsheet_token` / `sheet_id` / `sheet_name`（XOR）。浮动图片是 sheet 级对象——和单元格内嵌图片不同（后者走 `lark_sheets_cells_set`）。

### `lark_sheets_float_image_list`

```
lark_sheets_float_image_list(url="...", sheet_id="$SID")
```

### `lark_sheets_float_image_create`

所有字段拍平为独立 flag：图片来源 `image` / `image_token` / `image_uri`（三选一 XOR）/ `image_name` / `position_row` / `position_col` / `size_width` / `size_height` / `offset_row` / `offset_col` / `z_index`。

```
# 首选：直接给本地图片路径，CLI 自动上传（无需手动拿 token）
# 注意：image_name 是 required（即使路径 basename 已经是 logo.png 也要显式传）
lark_sheets_float_image_create(url="...", sheet_id="$SID", image="./logo.png", image_name="logo.png", position_row="2", position_col="B", size_width="300", size_height="200", z_index="1")

# 用已有 file_token（从 `lark_sheets_float_image_list` 的 image_token 或 `lark_sheets_cells_set_image` 返回的 file_token）
lark_sheets_float_image_create(url="...", sheet_id="$SID", image_name="logo.png", image_token="$TOKEN", position_row="0", position_col="A", size_width="200", size_height="150")

# 用 reference_id（图片上传链路返回的 image reference_id；与 image_token 二选一）
lark_sheets_float_image_create(url="...", sheet_id="$SID", image_name="logo.png", image_uri="$IMAGE_URI", position_row="2", position_col="B", size_width="300", size_height="200", z_index="1")
```

### `lark_sheets_float_image_update`

> **update ≈ create，只有图片源可省**：`manage_float_image` 工具的 update 要求和 create 相同的核心字段——`image_name`、`position_row` / `position_col` / `size_width` / `size_height` **全部必填**；唯一区别是**图片源（`image_token` / `image_uri`）可以全省**，省略即保留原图。这**不是**"只发改动字段"的 patch：缺任一核心字段会被工具拒绝（`lark_sheets_float_image_list` 不回传 `image_name`，CLI 无法替你回填）。
>
> 推荐流程：先 `lark_sheets_float_image_list(float_image_id="<id>")` 回读当前 position / size，再带上 `image_name` 和完整的 position / size 调一次 `lark_sheets_float_image_update`。

```
# 调整位置 + 尺寸，保留原图（不传图片源）
lark_sheets_float_image_update(url="...", sheet_id="$SID", float_image_id="$IMG_ID", image_name="logo.png", position_row="5", position_col="C", size_width="300", size_height="200")

# 换图：额外带 image_token，核心字段同样要给全
lark_sheets_float_image_update(url="...", sheet_id="$SID", float_image_id="$IMG_ID", image_name="new-logo.png", image_token="$NEW_TOKEN", position_row="5", position_col="C", size_width="300", size_height="200")
```

### `lark_sheets_float_image_delete`

```
lark_sheets_float_image_delete(url="...", sheet_id="$SID", float_image_id="$IMG_ID")
```

### Validate / DryRun / Execute 约束

- `Validate`：XOR 公共四件套；`lark_sheets_float_image_create` 要求 `image` / `image_token` / `image_uri` **恰好给一个**，`position_row` / `position_col` 与 `size_width` / `size_height` 必填且为合法整数；传 `image` 时还会校验路径安全（绝对路径 / 越出工作目录会被拒，`dry_run` 同样拦）。`lark_sheets_float_image_update` 必须 `float_image_id`，并和 create 一样必填 `image_name` / `position_row` / `position_col` / `size_width` / `size_height`（缺任一核心字段本地直接报错，不会静默发 0）；图片源 `image_token` / `image_uri` 可省（省略保留原图），给则二选一；`lark_sheets_float_image_delete` 强制 `yes` 或 `dry_run`。
- `DryRun`：写操作输出"将要 POST/PATCH/DELETE 的 float_image 请求模板"；传 `image` 时会多打印一步本地图片上传（`POST /open-apis/drive/v1/medias/upload_all`，`parent_type=sheet_image`）。
- `Execute`：写后不自动回读；如需确认，自行调用 `lark_sheets_float_image_list(float_image_id="<id>")` 比对新位置 / 尺寸。
