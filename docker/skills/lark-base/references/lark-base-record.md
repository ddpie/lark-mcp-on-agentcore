# base record shortcuts

record 相关命令索引。

## 命令导航

| 文档 | 命令 | 说明 |
|------|------|------|
| `lark_get_skill(domain="base", section="data-analysis-sop")` | `+record-get` / `+record-search` / `+record-list` / `+data-query` / 视图筛选排序 | 数据查询与分析统一选路、筛选排序投影、聚合后回查明细 SOP |
| `lark_get_skill(domain="base", section="record-upsert")` | `+record-upsert` | 创建或更新记录 |
| `lark_get_skill(domain="base", section="record-batch-create")` | `+record-batch-create` | 按 `fields/rows` 批量创建记录 |
| `lark_get_skill(domain="base", section="record-batch-update")` | `+record-batch-update` | 批量更新记录 |
| `help` | `+record-upload-attachment` | 上传一个或多个本地文件到附件字段 |
| `help` | `+record-download-attachment` | 下载一个或多个 Base 附件到本地；Base 附件必须用这个命令下载 |
| `help` | `+record-remove-attachment` | 删除附件字段中的一个或多个附件 |
| `lark_get_skill(domain="base", section="record-delete")` | `+record-delete` | 删除一条或多条记录 |
| `lark_get_skill(domain="base", section="record-share-link-create")` | `+record-share-link-create` | 生成记录分享链接（支持单条或批量，最多 100 条）|

## 说明

- 读取记录前优先阅读 `lark_get_skill(domain="base", section="data-analysis-sop")`，它合并了 `record / view / data-query` 的选路、分页、投影、聚合后回查明细和 link 关联读取。
- 聚合页只保留目录职责；写入、删除、历史等命令的详细说明请进入对应单命令文档。
- 所有 `+xxx-list` 调用都必须串行执行；若要批量跑多个 list 请求，只能串行执行。
- `+record-list` 支持重复传参 `--field-id` 做字段筛选。
- `+record-get` 支持重复 `--record-id` 或 `--json '{"record_id_list":[...]}'` 批量读取；也支持重复传参 `--field-id` 裁剪返回字段，避免返回全字段。
- 写记录 JSON 前优先阅读 `lark_get_skill(domain="base", section="cell-value")`。
- 本地文件写入一个或多个附件字段时，必须使用 `+record-upload-attachment`。
- 从附件字段下载一个或多个文件时，用 `+record-download-attachment`。
- 删除附件字段里的文件时，用 `+record-remove-attachment --yes`。
