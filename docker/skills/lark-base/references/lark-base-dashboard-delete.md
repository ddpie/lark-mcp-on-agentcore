# base +dashboard-delete

> **前置条件：** 先阅读 `lark_get_skill(domain="base", section="dashboard")` 了解整体工作流。

删除仪表盘（会同时删除其下所有组件，不可恢复）。

## 推荐命令

```
lark_base_dashboard_delete(base_token="VwGhb**************fMnod", dashboard_id="blkxxxxxxx")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token |
| `dashboard_id <id>` | 是 | 仪表盘 ID |

## 返回示例

```json
{
  "dashboard_id": "blkxxxxxxxxxxxx",
  "deleted": true
}
```

## 返回重点

| 字段 | 说明 |
|------|------|
| `dashboard_id` | 被删除的仪表盘 ID |
| `deleted` | 是否删除成功 |

> [!CAUTION]
> 这是**写入操作**且**不可逆** — 执行前必须向用户确认。删除仪表盘会同时删除其下所有组件，不可恢复。

## 参考

- `lark_get_skill(domain="base", section="dashboard")` — dashboard 模块指引
