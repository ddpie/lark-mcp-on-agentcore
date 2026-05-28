# lark-contact

## 选哪个工具

**user 身份和 bot 身份是两条完全独立的路径**。MCP server 始终使用 user 身份，按下表选工具:

| 想做什么 | user 身份 | bot 身份 |
|---|---|---|
| 按姓名 / 邮箱搜员工拿 open_id | `lark_contact_search_user` (参见 `lark_get_skill(domain="contact", section="search-user")`) | 不支持 |
| 已知 open_id 取他人资料 | `lark_contact_search_user(user_ids="<id>")` | ⚠️ 需要 bot 身份，MCP server 不可用 |
| 查看自己 | `lark_contact_get_user()` 或 `lark_contact_search_user(user_ids="me")` | 不支持 |

已知 open_id 只是想发消息 / 排日程,不必经过 contact —— 直接用 `lark_get_skill(domain="im")` / `lark_get_skill(domain="calendar")`。

## 典型场景

```
# 找张三给他发消息:先搜,确认 open_id,再发
lark_contact_search_user(query="张三", has_chatted=true)
lark_im_messages_send(user_id="ou_xxx", text="Hi!")
```

搜索命中多条且后续操作有副作用(发消息、邀请会议等),把候选列给用户挑;不要擅自选第一条。

## 注意事项

- **41050 / Permission denied** 受当前身份的可见范围限制(两条工具都可能遇到)。需要管理员调整可见范围。
- **跨租户用户**(`is_cross_tenant=true`)多数业务字段为空字符串,这是飞书可见性规则,下游做空值兜底。
- **ID 类型**:默认 `open_id`。`lark_contact_get_user` 可用 `user_id_type="union_id"` 或 `"user_id"`；`lark_contact_search_user` 只接受 `open_id`。

## 不在本 skill 范围

- 发消息 / 查聊天记录 → `lark_get_skill(domain="im")`
- 排日程 / 邀请会议 → `lark_get_skill(domain="calendar")`
- 部门树 / 按部门列员工 / 组织架构 → `lark_get_skill(domain="openapi-explorer")`
