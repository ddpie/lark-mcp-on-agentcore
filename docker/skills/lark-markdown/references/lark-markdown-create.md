# markdown +create

在 Drive 中创建一个原生 Markdown 文件（`.md`），支持创建到普通 Drive 文件夹或 Wiki 节点下。

## 用法

```
# 直接用行内内容创建
lark_markdown_create(name="README.md", content="# Hello")

# 从本地 .md 文件创建
lark_markdown_create(file="./README.md")

# 创建到指定文件夹
lark_markdown_create(folder_token="fldcn_xxx", file="./README.md")

# 创建到指定 wiki 节点
lark_markdown_create(wiki_token="wikcn_xxx", file="./README.md")
```

## 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `folder_token` | 否 | 目标 Drive 文件夹 token；与 `wiki_token` 互斥；省略时创建到根目录 |
| `wiki_token` | 否 | 目标 wiki 节点 token；与 `folder_token` 互斥；传入后自动映射为 `parent_type=wiki` |
| `name` | 条件必填 | 文件名，**必须显式带 `.md` 后缀**；使用 `content` 时必填；使用 `file` 时可省略，默认取本地文件名 |
| `content` | 条件必填 | Markdown 内容；与 `file` 互斥；支持直接传字符串、`@file`、`-`（stdin） |
| `file` | 条件必填 | 本地 `.md` 文件路径；与 `content` 互斥 |

## 关键约束

- `content` 与 `file` 必须二选一
- `folder_token` 与 `wiki_token` 互斥
- `name` 必须带 `.md` 后缀
- `file` 指向的本地文件名也必须带 `.md` 后缀
- 传 `wiki_token` 时，返回值中不会附带 `/file/<token>` URL，因为 wiki 承载文件没有稳定的独立 file URL

## 返回值

```json
{
  "ok": true,
  "identity": "user",
  "data": {
    "file_token": "boxcnxxxx",
    "file_name": "README.md",
    "size_bytes": 1234
  }
}
```

> [!IMPORTANT]
> ⚠️ 以应用身份（bot identity）创建 Markdown 文件的操作需要 bot identity，不通过 MCP server 提供。MCP server 始终使用 user identity。

## 参考

- `lark_get_skill(domain="markdown")` — Markdown 域总览
