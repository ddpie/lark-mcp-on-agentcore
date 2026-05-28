# base +view-get-visible-fields

获取可见字段配置。

## 1. 顶层规则

- 读取当前视图的可见字段列表与顺序。
- 仅 `grid` / `kanban` / `gallery` / `calendar` / `gantt` 视图支持。

## 2. 推荐命令

```
lark_base_view_get_visible_fields(base_token="<base_token>", table_id="<table_id>", view_id="<view_id>")
```

## 3. 返回重点

- 返回当前视图可见字段列表。
- 返回结果中的主字段会位于第一位。

## 参考

- `lark_get_skill(domain="base", section="view")` — view 索引页
