# apps db-env-create

把存量单库应用初始化为 `dev` / `online` 多环境数据库。

## 何时用

仅用于存量单库应用需要拆成 `dev` / `online` 两套数据库的场景。普通查看表、查 schema、执行 SQL 不需要先初始化。注意：通过 `lark_apps_create(app_type="full_stack")` 新建的应用通常已自带多环境，无需再初始化（重复初始化会返回「已初始化」错误）。

## 命令骨架

- 必填：`app_id`。
- `env`：要创建的环境，由调用方传入，目前只支持 `dev`（默认 `dev`）。
- `sync_data`：bool 开关，传 `sync_data=true` 则把现有 online 数据复制到新环境；不传则不复制（默认）。
- 这是 high-risk-write 操作；单库拆成 dev/online 后不可逆。

## 示例

```
lark_apps_db_env_create(app_id="app_xxx", env="dev", dry_run=true)
lark_apps_db_env_create(app_id="app_xxx", env="dev", sync_data=true, _confirm=true)
```

## 输出契约

- 成功读取 `data.status`、`data.environments`、`data.data_synced`。
- 未确认时 MCP server 会先拒绝并给出高风险确认指引；向用户确认后再带 `_confirm=true` 重试。
- 如果服务端提示已启用多环境（`Multi-env is already initialized`），转述状态即可，不要重复初始化。

## Agent 规则

不要静默确认。遇到高风险确认提示时，先向用户说明不可逆风险；用户明确同意后才带 `_confirm=true` 重试。
