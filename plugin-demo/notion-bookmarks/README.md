# Notion 书签收藏 (`notion-bookmarks`)

参考 [`lengsukq/nav-notion-lime`](https://github.com/lengsukq/nav-notion-lime) 的 Notion 数据库模型与增删改查逻辑，为 **Lumakey Plugin v3** 打造的官方外置书签收藏插件示例。

## 特性

- **完全互通 `nav-notion-lime` 数据库结构**：自动读取数据库 Schema，兼容中英文列名（`name`/`Title`/`名称`、`url`/`URL`/`链接`、`description`/`描述`、`tag`/`tags`/`标签`、`category`/`分类`、`priority`/`优先级`、`pinned`/`置顶`），无论 `url` 列是 Notion `url` 类型还是 `rich_text` 链接类型均可正常读写。
- **主搜索栏免前缀直搜**：同步或增删改书签时自动导出 `search-index.json`，无需输入 `bm` 前缀即可在 Lumakey `⌥Space` 搜索栏直接通过书签名称、拼音首字母、URL 或 `#标签` 秒搜书签并回车直达（`⌘Return` 可进入插件管理卡片）。
- **零常驻、零依赖、纯沙盒**：显式声明 `"capabilities": []`，仅使用 macOS 自带 `/usr/bin/python3` 标准库；本地缓存（默认 120s）保证日常搜索毫秒级响应。
- **一键收藏与自动抓取元信息**：支持直接从剪贴板识别链接一键入库，并自动抓取目标网页 `og:title` / `<title>` 与 `description`。
- **卡片内闭环管理**：通过 `commandArgs` 在 Lumakey 液态玻璃卡片内直接完成刷新同步、置顶/取消置顶、提高优先级与归档删除。

## Notion 数据库配置

与 `nav-notion-lime` 保持一致：
1. 在 [Notion Integrations](https://www.notion.so/my-integrations) 创建 Internal Integration 并复制 Secret Token（`ntn_...`）。
2. 打开你的 Notion 书签表格数据库，点击右上角 **`...` → Connect to** 授权该 Integration。
3. 复制数据库链接（或 32 位 Database ID）填入 Lumakey 插件中心配置表单并保存。

## 搜索框命令示例

假设触发关键词为 `bm`（也可使用 `bookmark`、`notion`、`nav`）：

| 指令 | 说明 |
| :--- | :--- |
| `bm` | 打开书签列表；若剪贴板包含网址，顶部会显示「一键收藏剪贴板链接」按钮 |
| `bm github` | 按标题、链接、简介关键字过滤书签 |
| `bm #开发` | 按标签或分类筛选书签 |
| `bm add https://example.com` | 收藏链接并自动抓取网页标题与描述 |
| `bm add https://example.com 自定义标题 #工具 #AI` | 指定标题和标签收藏到 Notion |
| `bm add` | 直接收藏当前剪贴板中的链接 |
| `bm edit github title=GitHub主页 pin=true priority=20` | 修改匹配书签的字段 |
| `bm pin github` / `bm unpin github` | 置顶或取消置顶匹配书签 |
| `bm del github` | 将匹配书签归档（`archived: true`） |
| `bm refresh` | 强制从 Notion 重新同步最新数据 |

## 运行内置单元测试

```bash
python3 -m unittest discover -s plugin-demo/notion-bookmarks -p "test_*.py" -v
```
