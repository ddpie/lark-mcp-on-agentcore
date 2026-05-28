
# calendar +freebusy

查询用户主日历的忙闲信息，返回指定时间范围内的忙碌时段列表和rsvp的状态。

需要的scopes: ["calendar:calendar.free_busy:read"]

## 工具调用

```
# 查询当前用户今天的忙闲（默认）
lark_calendar_freebusy()

# 自定义时间范围（仅日期）
lark_calendar_freebusy(start="2026-03-11", end="2026-03-12")

# 自定义时间范围（完整 ISO 8601）
lark_calendar_freebusy(start="2026-03-11T08:00:00+08:00", end="2026-03-11T18:00:00+08:00")

# 查询指定用户的忙闲信息
lark_calendar_freebusy(start="2026-03-11", end="2026-03-12", user_id="ou_xxx")

# 人类可读格式输出
lark_calendar_freebusy(format="pretty")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `start` | 否 | 查询开始时间（ISO 8601 或仅日期，默认当天） |
| `end` | 否 | 查询结束时间（默认与 `start` 属于同一天，自动取当天结束时间） |
| `user_id` | 否 | 目标查询用户 ID（`ou_` 前缀）。省略时默认查询当前登录用户 |
| `format` | 否 | 输出格式：json（默认） \| pretty |

## 时间格式

`start` 和 `end` 支持以下格式：

| 格式 | 示例 | 说明 |
|------|------|------|
| ISO 8601 | `2026-03-11T09:00:00+08:00` | 完整格式 |
| 日期+时间 | `2026-03-11 09:00:00` | 自动补全时区 |
| 仅日期 | `2026-03-11` | start 取 00:00:00，end 取 23:59:59 |
| Unix 时间戳 | `1741564800` | 秒级时间戳 |

## 输出示例

### 表格格式

```
start             end               rsvp_status
----------------  ----------------  -----------
2026-03-11 10:00  2026-03-11 10:30  接受
2026-03-11 14:00  2026-03-11 15:00  待定

共 2 个忙碌时段
```

### JSON 格式

```json
[
  {
    "start_time": "2026-03-11T10:00:00+08:00",
    "end_time": "2026-03-11T10:30:00+08:00",
    "rsvp_status": "accept"
  },
  {
    "start_time": "2026-03-11T14:00:00+08:00",
    "end_time": "2026-03-11T15:00:00+08:00",
    "rsvp_status": "tentative"
  }
]
```

## 典型场景

### 1. 查找日程会议空闲时段

```
# 查询今天的忙碌时段
lark_calendar_freebusy()

# 查询工作时间段
lark_calendar_freebusy(start="2026-03-11T08:00:00+08:00", end="2026-03-11T18:00:00+08:00")
```

### 2. 检查团队成员可用性

```
# 查询多个成员，对比找出共同空闲时间
lark_calendar_freebusy(start="2026-03-12", user_id="ou_member_a")
lark_calendar_freebusy(start="2026-03-12", user_id="ou_member_b")
```

## 注意事项

1. **只查询主日历** — 此工具只返回用户主日历的忙闲信息，不包括其他订阅日历
2. **隐私保护** — 只返回忙碌时段的起止时间，不包含日程标题、描述等详细信息

## 与其他工具对比

| 工具 | 用途 | 输出内容 |
|------|------|----------|
| `lark_calendar_freebusy` | 查询忙闲时段 | 只返回忙碌时段列表（无日程详情） |
| `lark_calendar_agenda` | 查看日程安排 | 返回完整日程列表（含标题、描述等） |

**选择建议**：
- **仅需了解是否有空** → 使用 `lark_calendar_freebusy`（更快，隐私保护）
- **需要查看日程详情** → 使用 `lark_calendar_agenda`

## 参考

- lark_get_skill(domain="calendar", section="agenda") — 查看日程安排
- lark_get_skill(domain="calendar", section="create") — 创建日程
- lark_get_skill(domain="calendar", section="suggestion") — 根据非明确时间或一段时间范围，推荐多个可用时间块方案
- lark_get_skill(domain="calendar") — 日历完整 API
