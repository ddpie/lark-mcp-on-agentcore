# base view shortcuts

view 相关命令索引。

## 命令导航

| 文档 | 命令 | 说明 |
|------|------|------|
| `lark_get_skill(domain="base", section="view-list")` | `+view-list` | 分页列视图 |
| `lark_get_skill(domain="base", section="view-get")` | `+view-get` | 获取视图基本信息 |
| `lark_get_skill(domain="base", section="view-create")` | `+view-create` | 创建视图 |
| `lark_get_skill(domain="base", section="view-delete")` | `+view-delete` | 删除视图 |
| `lark_get_skill(domain="base", section="view-rename")` | `+view-rename` | 重命名视图 |
| `lark_get_skill(domain="base", section="view-get-filter")` | `+view-get-filter` | 读取筛选配置 |
| `lark_get_skill(domain="base", section="view-set-filter")` | `+view-set-filter` | 更新筛选配置 |
| `lark_get_skill(domain="base", section="view-get-visible-fields")` | `+view-get-visible-fields` | 读取可见字段列表 |
| `lark_get_skill(domain="base", section="view-set-visible-fields")` | `+view-set-visible-fields` | 更新可见字段列表 |
| `lark_get_skill(domain="base", section="view-get-group")` | `+view-get-group` | 读取分组配置 |
| `lark_get_skill(domain="base", section="view-set-group")` | `+view-set-group` | 更新分组配置 |
| `lark_get_skill(domain="base", section="view-get-sort")` | `+view-get-sort` | 读取排序配置 |
| `lark_get_skill(domain="base", section="view-set-sort")` | `+view-set-sort` | 更新排序配置 |
| `lark_get_skill(domain="base", section="view-get-timebar")` | `+view-get-timebar` | 读取时间轴配置 |
| `lark_get_skill(domain="base", section="view-set-timebar")` | `+view-set-timebar` | 更新时间轴配置 |
| `lark_get_skill(domain="base", section="view-get-card")` | `+view-get-card` | 读取卡片配置 |
| `lark_get_skill(domain="base", section="view-set-card")` | `+view-set-card` | 更新卡片配置 |

## AI 决策前置

先判断视图类型，再选接口能力；不支持的能力直接不要调用。

| 视图类型 | 可用能力 |
|------|------|
| `grid` | `group` `sort` `filter` `visible_fields` |
| `kanban` | `group` `sort` `filter` `card` `visible_fields` |
| `gallery` | `sort` `filter` `card` `visible_fields` |
| `calendar` | `filter` `timebar` `visible_fields` |
| `gantt` | `group` `sort` `filter` `timebar` `visible_fields` |

## 说明

- 聚合页只保留目录职责；每个命令的详细说明请进入对应单命令文档。
- 所有 `+xxx-list` 调用都必须串行执行；若要批量跑多个 list 请求，只能串行执行。
