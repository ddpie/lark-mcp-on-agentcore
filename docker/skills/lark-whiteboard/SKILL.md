# 飞书画板

飞书画板：查询和编辑飞书云文档中的画板。支持导出画板为预览图片、导出原始节点结构、使用 DSL（转成 OpenAPI 格式）、PlantUML/Mermaid 格式更新画板内容。
当用户需要查看画板内容、导出画板图片、编辑画板，或是需要可视化表达架构、流程、组织关系、时间线、因果、对比等结构化信息时使用此 skill，无论是否提及"画板"。

---

## 快速决策

| 用户需求 | 行动 |
|---|---|
| 查看画板内容 / 导出图片 | `lark_whiteboard_query(whiteboard_token="xxx", output_as="image", output="./preview.png")` — 详见 `lark_get_skill(domain="whiteboard", section="query")` |
| 获取画板的 Mermaid/PlantUML 代码 | `lark_whiteboard_query(whiteboard_token="xxx", output_as="code")` — 详见 `lark_get_skill(domain="whiteboard", section="query")` |
| 检查画板是否由代码绘制 | `lark_whiteboard_query(whiteboard_token="xxx", output_as="code")` — 详见 `lark_get_skill(domain="whiteboard", section="query")` |
| 修改节点文字/颜色（简单改动）| `lark_whiteboard_query(output_as="raw")` → 手动改 JSON → `lark_whiteboard_update(input_format="raw")` |
| 用户**已提供** Mermaid/PlantUML 代码，或明确指定用该格式 | 自己生成/使用代码 → `lark_whiteboard_update(input_format="mermaid")` 或 `lark_whiteboard_update(input_format="plantuml")` — 详见 `lark_get_skill(domain="whiteboard", section="update")` |
| 绘制复杂图表（架构/流程/组织等）| → **[§ 创作 Workflow](#创作-workflow)** |
| 修改/重绘已有复杂画板 | → **[§ 修改 Workflow](#修改-workflow)** |

> **⚠️ 强制规范（通过 stdin 更新）**：
> 数据来源于本地文件时，**必须**使用 `source="-"` 配合 `input_format`。
> 例：`cat chart.mmd | lark_whiteboard_update(whiteboard_token="xxx", source="-", input_format="mermaid")`

## Shortcuts

| Shortcut | 说明 |
|---|---|
| `lark_whiteboard_query` | 查询画板，导出为预览图片、代码或原始节点结构 — 详见 `lark_get_skill(domain="whiteboard", section="query")` |
| `lark_whiteboard_update` | 更新画板，支持 PlantUML、Mermaid 或 OpenAPI 原生格式 — 详见 `lark_get_skill(domain="whiteboard", section="update")` |

---

## 创作 Workflow

> 此 workflow 用于**独立创作一个画板**。
> 需要在文档中批量创建多个画板时，由 lark-doc 负责调度，见 `lark_get_skill(domain="doc", section="whiteboard")`。

**Step 1：获取 board_token**

| 用户给了什么 | 怎么获取 |
|---|---|
| 直接给了 whiteboard token（`wbcnXXX`）| 直接使用 |
| 文档 URL 或 doc_id，文档中已有画板 | `lark_docs_fetch(api_version="v2", doc="<URL>")`，从返回的 `<whiteboard token="xxx"/>` 提取 |
| 文档 URL 或 doc_id，需要新建画板 | `lark_docs_update(api_version="v2", doc="<doc_id>", command="append", content='<whiteboard type="blank"></whiteboard>')`，从响应 `data.new_blocks[0].block_token` 取得（`block_type == "whiteboard"` 的那条；参数详见 lark_get_skill(domain="doc")）|

**Step 2：渲染 & 写入**

→ 进入 **[§ 渲染 & 写入画板](#渲染--写入画板)** 章节，按流程完成后直接返回结果给用户。

---

## 修改 Workflow

**Step 1：获取 board_token**（同创作 Workflow Step 1）

**Step 2：判断修改策略**

```
lark_whiteboard_query(output_as="code")
  ├─ 返回 Mermaid/PlantUML 代码
  │   → 在原代码上修改 → lark_whiteboard_update(input_format="mermaid") 或 plantuml
  ├─ 无代码（DSL 或其他方式绘制的画板）
  │   ├─ 只改文字/颜色 → lark_whiteboard_query(output_as="raw") → 手动改 JSON → lark_whiteboard_update(input_format="raw")
  │   └─ 重绘/结构调整 → lark_whiteboard_query(output_as="image") → 看图后进入 [§ 渲染 & 写入画板]
  └─ 用户有明确要求 → 以用户要求优先
```

---

## 渲染 & 写入画板

### 渲染路由

**先自报身份**：按训练来源，你属于哪一家？`Claude` / `Gemini` / `GPT` / `GLM` / `Doubao 或 Seed` / `Other`。身份决定 SVG / DSL 分流（不同家族对这两种表达语言的能力不均衡），不要跳过这一步。

**然后按图表类型 × 身份选路径**，读对应文件按其完整 workflow 执行（含读 scene 指南、生成内容、渲染审查、交付）：

| 图表类型 | 身份 | 路径 |
|---|---|---|
| 思维导图、时序图、类图、饼图、甘特图 | 任何身份 | `lark_get_skill(domain="whiteboard", section="mermaid")` — routes/mermaid.md |
| 其他图表 | `Claude` / `Gemini` / `GPT` / `GLM` | `lark_get_skill(domain="whiteboard", section="svg")` — routes/svg.md |
| 其他图表 | `Doubao` / `Seed` / `Other` | `lark_get_skill(domain="whiteboard", section="dsl")` — routes/dsl.md |

> **⚠️ SVG 路径失败回退**：走 routes/svg.md 时，碰到以下情况之一 → **丢弃当前 SVG，改读 routes/dsl.md 从零重画，不要逐行修补**：
> - 渲染命令直接报错（语法级崩溃，不是 `--check` 的 warn/error）
> - 两轮改写仍无法消除 `--check` 的 `text-overflow` error
> - 目测 PNG 视觉严重错乱（文字大面积溢出、元素重叠压住关键信息、布局整体崩溃）
>
> SVG 源码修补常常引入新 bug，换 DSL 从零重画往往更稳。这是 SVG 路径自由发挥的硬兜底，不要侵入 routes/svg.md 的创作流程。

### 产物规范

产物目录：`./diagrams/YYYY-MM-DDTHHMMSS/`（本地时间，不含冒号和时区后缀）。如用户指定路径，以用户为准。

目录内固定文件名：

```
diagram.svg           ← SVG 源码（SVG 路径）
diagram.mmd           ← Mermaid 源码（Mermaid 路径）
diagram.json          ← DSL 源文件（DSL 路径） / OpenAPI JSON（SVG 路径从 diagram.svg 导出）
diagram.gen.cjs       ← 坐标计算脚本（仅 DSL 脚本构建方式）
diagram.png           ← 渲染结果
```

### 写入画板

> [!CAUTION]
> **写入前强制 dry-run**：向已有内容的画板写入时，必须先加 `overwrite=true` 配合 dry-run 探测。
> 输出含 `XX whiteboard nodes will be deleted` → 必须向用户确认后才能执行。

```bash
# 第一步：dry-run 探测
npx -y @larksuite/whiteboard-cli@^0.2.11 -i <产物文件> --to openapi --format json \
  | lark_whiteboard_update(whiteboard_token="<Token>", source="-", input_format="raw", idempotent_token="<10+字符唯一串>", overwrite=true, _confirm=false)

# 第二步：确认后执行
npx -y @larksuite/whiteboard-cli@^0.2.11 -i <产物文件> --to openapi --format json \
  | lark_whiteboard_update(whiteboard_token="<Token>", source="-", input_format="raw", idempotent_token="<10+字符唯一串>", overwrite=true, _confirm=true)
```

> `idempotent_token` 最少 10 字符，建议用时间戳+标识拼接（如 `1744800000-board-1`），避免重试导致重复写入。
