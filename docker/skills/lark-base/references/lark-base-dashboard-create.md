# base +dashboard-create

> **前置条件：** 先阅读 `lark_get_skill(domain="base", section="dashboard")` 了解整体工作流。

创建空白仪表盘。创建成功后务必记录返回的 `dashboard_id`，后续添加组件和管理仪表盘都需要用到。

## 关键约束

- **dashboard_id** 在 create 返回中取得，后续 get/update/delete 使用。

## 推荐命令

```
# 创建仪表盘
lark_base_dashboard_create(base_token="VwGhb**************fMnod", name="销售报表")

# 创建仪表盘（指定主题）
lark_base_dashboard_create(base_token="VwGhb**************fMnod", name="销售报表", theme_style="default")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token |
| `name <name>` | 是 | 仪表盘名称 |
| `theme_style <style>` | 否 | 主题风格（见下方枚举） |

### theme-style 枚举

| 值 | 说明 |
|------|------|
| `default` | 默认主题 |
| `SimpleBlue` | 简约蓝 |
| `DarkGreen` | 深绿 |
| `summerBreeze` | 夏日微风 |
| `simplistic` | 简洁 |
| `energetic` | 活力 |
| `deepDark` | 深色 |
| `futuristic` | 未来感 |

## 返回示例

```json
{
  "dashboard_id": "blkxxxxxxxxxxxx",
  "name": "数据分析仪表盘",
  "theme": {
    "theme_style": "default"
  }
}
```

## 返回重点

| 字段 | 说明 |
|------|------|
| `dashboard_id` | 仪表盘 ID（如 `blkxxxxxxxxxxxx`），后续操作都需要用到，务必记录 |
| `name` | 仪表盘名称 |
| `theme.theme_style` | 主题风格 |

> [!CAUTION]
> 这是**写入操作** — 执行前必须向用户确认。

## 参考

- `lark_get_skill(domain="base", section="dashboard")` — dashboard 模块指引
