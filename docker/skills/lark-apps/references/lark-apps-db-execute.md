# apps db-execute

经妙搭服务端在应用数据库执行 SQL。

## 何时用

用于通过妙搭服务端执行应用数据库 SQL。不要从环境变量里取连接串裸连数据库；本地调试也走这个工具。

## 命令骨架

- 必填：`app_id`，以及 `sql` / `file` 二选一（互斥）。
- `sql`：内联 SQL 文本。
- `file`：`.sql` 文件路径，需为工作目录内的相对路径（如 `./migration.sql`）；绝对路径、或经 `..`/符号链接越出工作目录的路径会被拒绝。文件不在工作目录内时，改用 `sql` 直接传入内容。
- `env` 枚举：`dev` / `online`，**默认 `dev`**；需要操作线上环境数据库时，显式指定 `env="online"`。
- 这是 high-risk-write 操作（SQL 可含 DML/DDL）：任何执行都需 `_confirm=true`，否则 MCP server 会先拒绝并给出高风险确认指引。`dry_run=true` 预览不需要确认。
- 始终以 `transactional=false` 执行；不默认包事务。

## 示例

```
lark_apps_db_execute(app_id="app_xxx", env="dev", sql="select * from orders limit 5", _confirm=true)
lark_apps_db_execute(app_id="app_xxx", env="dev", file="./migration.sql", dry_run=true)
```

## 输出契约

- 成功默认 JSON 读取 `data.results[]`；每个元素对应一条 SQL，常见字段有 `sql_type`、`data`、`record_count`、`affected_rows`。
- 失败可能仍有前序语句已执行；此时输出 `ok:false` 的 envelope，从 `data` 读 `results[]`（全部逐条结果，失败语句 `sql_type` 为 `ERROR`）、`statement_index`、`error_code`、`error_message`、`rolled_back` 和 `note`，决定从哪条继续。

## Agent 规则

- 该操作为 high-risk-write，执行一律需 `_confirm=true`；不确认会被 MCP server 先拒绝并给出确认指引。
  - **只读查询、以及不删除/不丢失既有数据且可撤回的语句**：已授权时可直接带 `_confirm=true` 执行。
  - **会删除或丢失既有数据、或难以撤回的语句**：先 `dry_run=true` 预览（无需确认），向用户确认后再带 `_confirm=true` 执行；不要在用户不知情时自动确认。
- 多语句失败时，失败前的语句可能已经 auto-commit。不要整批重跑；按错误 detail/hint 修失败语句，并从剩余语句继续。
- 如果需要原子性，让用户在 SQL 内显式写 `BEGIN` / `COMMIT`，不要假设会包事务。
- 不要把数据库连接串从 env 中取出来裸连。
