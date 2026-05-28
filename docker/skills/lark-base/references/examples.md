# 飞书多维表格使用场景完整示例（base）

本文档提供基于 `lark_base_*` 工具的完整示例。

> **返回**: `lark_get_skill(domain="base")` | **参考**: `lark_get_skill(domain="base", section="shortcut-field-properties")` · `lark_get_skill(domain="base", section="cell-value")`

---

## 场景 1：用 unified Shortcut 快速建表

适合已经明确字段结构、希望一次性完成建表的场景。

```
lark_base_table_create(base_token="bascnXXXXXXXX", name="客户管理表", fields='[{"name":"客户名称","type":"text","description":"主标题字段"},{"name":"负责人","type":"user","multiple":false,"description":"用于标记客户跟进的直接负责人"},{"name":"签约日期","type":"datetime"},{"name":"状态","type":"select","multiple":false,"options":[{"name":"进行中"},{"name":"已完成"}]}]')
```

---

## 场景 2：创建数据表并查看字段

适合需要先建表、再确认字段结构的场景。

### 步骤 1：在已有 Base 中创建数据表

```
lark_base_table_create(base_token="bascnXXXXXXXX", name="客户管理表")
```

### 步骤 2：列出字段

```
lark_base_field_list(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", limit="100")
```

> 提示：Base token 统一通过 `base_token` 传入；表 ID 统一通过 `table_id` 传入。

---

## 场景 3：创建、读取、更新单条记录

### 新增记录

```
lark_base_record_upsert(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", json='{"客户名称":"字节跳动","负责人":[{"id":"ou_xxx"}],"状态":"进行中"}')
```

### 列出记录

```
lark_base_record_list(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", limit="100")
```

### 更新记录

```
lark_base_record_upsert(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", record_id="recXXXXXXXX", json='{"状态":"已完成"}')
```

### 删除记录

```
lark_base_record_delete(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", record_id="recXXXXXXXX", _confirm=true)
```

---

## 场景 4：配置视图筛选后按视图读取记录

需要筛选查询时，推荐先写视图筛选，再通过 `view_id` 读取记录。

### 更新视图筛选条件

```
lark_base_view_set_filter(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", view_id="vewXXXXXXXX", json='{"logic":"and","conditions":[{"field_name":"状态","operator":"is","value":["进行中"]}]}')
```

### 按视图读取记录

```
lark_base_record_list(base_token="bascnXXXXXXXX", table_id="tblXXXXXXXX", view_id="vewXXXXXXXX", limit="100")
```

---

## 场景 5：什么时候优先用 Shortcut

- 需要一次性建表并附带字段、视图时，优先 `lark_base_table_create`
- 需要按业务字段名做 upsert 时，优先 `lark_base_record_upsert`
- 需要配置筛选视图时，优先 `lark_base_view_set_filter`
- 需要记录历史时，优先 `lark_base_record_history_list`
