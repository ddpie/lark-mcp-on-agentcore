# apps +html-publish

把本地的 HTML 文件或目录部署为可访问的妙搭应用，响应返回应用的访问链接 `url`。

## 用法

```
# 发布整个目录
lark_apps_html_publish(app_id="app_xxx", path="./dist/")

# 发布单个 HTML 文件
lark_apps_html_publish(app_id="app_xxx", path="./index.html")
```

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `app_id` | 是 | 应用 ID。从 `lark_apps_create` 响应里拿；或者从用户给的妙搭应用链接 `https://miaoda.feishu.cn/app/app_xxx` 的 `/app/` 后面提取 |
| `path` | 是 | 本地文件或目录路径；目录会递归打包成 tar.gz。**必须含 `index.html`** |
| `allow_sensitive` | 否 | 跳过 Validate 的凭据文件扫描。默认不传；仅在用户明示要发布凭据示例文件时才加 |

## 返回值

**成功：**

```json
{
  "ok": true,
  "data": {
    "url": "https://miaoda.feishu.cn/app/app_4k5jepcbjmv6m"
  }
}
```

**失败：**

```json
{
  "ok": false,
  "error": {
    "type": "api_error",
    "message": "html-publish failed (code=90001): build failed: dependency conflict",
    "hint": "构建失败：检查打包文件清单"
  }
}
```

## 凭据文件拦截

Validate 阶段会扫描 `path` 下所有候选文件，命中以下任一模式 **直接拒绝**：

- `.env` / `.env.*`（环境变量 / API key）
- `.npmrc` / `.netrc`（HTTP 凭据）
- `.git-credentials`（Git over HTTPS 凭据）
- `.aws/credentials`、`.docker/config.json`、`.kube/config`（云 SDK 凭据）

**Agent 行为契约**：

- 默认必须从产物里清掉命中的文件后再 publish
- 只有当用户**明确**意图是 shipping 凭据示例（文档 / 教程站等）时，才追加 `allow_sensitive=true` 旁路

## 提示

- `path` 既可以是 cwd（`.`）也可以是子目录或单文件；cwd 干净（没有命中凭据列表）就能发。仍然建议传具体子目录（`./dist`、`./public/` 等）以减少误打包风险
- `path` **必须**是 cwd 内的相对路径（如 `./dist`、`./index.html`）；绝对路径或越界路径会被拒绝
- 目录打包成 tar.gz 时**不做过滤**（`.git` / `node_modules` 等会一并打包，只有凭据 list 才会被 Validate 拦），让用户传干净的产物目录
- **不要**原样把 envelope JSON 转述给用户

## 参考

- `lark_get_skill(domain="apps")` — 妙搭应用全部命令
