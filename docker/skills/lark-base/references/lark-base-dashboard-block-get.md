# base +dashboard-block-get

> **前置条件：** 先阅读 `lark_get_skill(domain="base", section="dashboard")` 了解整体工作流。

获取仪表盘中单个组件的详情（包含 data_config 完整配置）。常用于：1) 查看组件的完整配置；2) 编辑组件前了解当前配置。

## 推荐命令

```
lark_base_dashboard_block_get(base_token="bascn***************CtadY", dashboard_id="blkxxx", block_id="chtxxxxxxxx")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `base_token <token>` | 是 | Base Token |
| `dashboard_id <id>` | 是 | 仪表盘 ID |
| `block_id <id>` | 是 | Block ID |
| `user_id_type <type>` | 否 | 用户 ID 类型：open_id / union_id / user_id |
| `format <fmt>` | 否 | 输出格式 |

## 返回示例

```json
{
  "block": {
    "block_id": "chtxxxxxxxx",
    "name": "柱状图",
    "type": "column",
    "data_config": {
      "table_name": "电商交易明细",
      "series": [{"field_name": "营销费用", "rollup": "SUM"}],
      "group_by": [{"field_name": "品类", "mode": "integrated"}]
    },
    "layout": {"x": 0, "y": 0, "w": 6, "h": 4}
  }
}
```

## 返回重点

| 字段 | 说明                            |
|------|-------------------------------|
| `block.block_id` | 组件 ID                         |
| `block.name` | 组件名称                          |
| `block.type` | 组件类型（如 `column`/`line`/`pie`） |
| `block.data_config` | 数据配置（新建/编辑组件时可基于此字段修改）        |
| `block.layout` | 布局信息（只读，x/y/w/h 坐标和尺寸）        |

## 参考

- `lark_get_skill(domain="base", section="dashboard")` — dashboard 模块指引
