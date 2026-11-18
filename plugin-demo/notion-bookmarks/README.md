# Notion 书签收藏 (`notion-bookmarks`)

参考 [`lengsukq/nav-notion-lime`](https://github.com/lengsukq/nav-notion-lime) 的 Notion 数据库模型与增删改查逻辑，基于 **原生 Swift 6 (`PluginKit` + `Foundation`)** 为 **Lucent Plugin v3** 打造的官方外置书签收藏插件。

## 核心特性

- **完全互通 `nav-notion-lime` 数据库结构**：自动读取数据库 Schema，兼容中英文列名，无论 `url` 列是 Notion `url` 类型还是 `rich_text` 链接类型均可正常读写。
- **主搜索栏免前缀直搜**：同步或增删改书签时自动导出 `search-index.json`，无需输入 `bm` 前缀即可在 Lucent `⌥Space` 搜索栏直接通过书签名称、拼音首字母、域名或 `#标签` 秒搜书签并回车直达（`⌘Return` 可进入插件管理卡片）。
- **原生 Swift 二进制、零常驻、零外部依赖**：预编译为 `arm64` 原生可执行文件 `bin/notion-bookmarks`，无需本机安装 Python 运行时；本地缓存（默认 `120s`）保证日常搜索毫秒级响应。
- **一键收藏与自动抓取元信息**：支持从剪贴板识别链接一键入库，并自动抓取目标网页 `og:title` / `<title>` 与 `description`。
- **卡片内闭环管理**：在 Lucent 卡片内直接完成刷新同步、表单编辑、置顶/取消置顶、提高优先级与归档删除。

## 一、获取 Notion Token 与授权数据库

1. **创建 Notion Integration 并复制 Token**
   - 打开 [Notion Integrations](https://www.notion.so/my-integrations)，点击 **New integration**。
   - 类型保持 **Internal**，选择你的目标 Workspace 并创建。
   - 复制生成的 Secret Token（通常以 `ntn_` 或 `secret_` 开头）。
2. **给书签数据库授权该 Integration（关键步骤）**
   - 在 Notion 中打开你的书签表格数据库页面。
   - 点击页面右上角 `...` → **Connections（或 Connect to）**，搜索并绑定你刚创建的 Integration。
   - *注：未完成此步授权时，插件请求会返回 `404` 找不到数据库。*
3. **获取 Database ID**
   - 复制该数据库页面的浏览器完整链接（形如 `https://www.notion.so/xxx/32位ID?v=...`）或直接提取 32 位 ID。
   - 插件会自动从完整 URL 中解析标准 UUID，无需手动截断。

## 二、Notion 数据库字段兼容说明

插件会自动读取数据库 Schema 并兼容以下中英文列名（`nav-notion-lime` 数据库可直接复用，无需修改表头）：

| 逻辑字段 | 支持的列名（任选其一） | 支持的 Notion 列类型 | 说明 |
| :--- | :--- | :--- | :--- |
| **标题**（必填） | `name` / `Title` / `名称` / `标题` | Title | 书签主标题 |
| **链接**（必填） | `url` / `link` / `链接` / `地址` | URL / Rich Text | 兼容纯文本链接与超链接 |
| **描述** | `description` / `desc` / `描述` / `说明` | Rich Text | 新增时可自动抓取网页简介 |
| **标签** | `tag` / `tags` / `标签` | Multi-select / Select / Rich Text | 支持 `#标签` 筛选与索引 |
| **分类** | `category` / `group` / `分类` / `分组` | Select / Rich Text | 会自动合并到标签检索中 |
| **优先级** | `priority` / `sort` / `优先级` | Number | 数值越大排序越靠前 |
| **置顶** | `pinned` / `pin` / `is_top` / `置顶` | Checkbox / Select（含「置顶」） | 置顶条目固定排在最前 |
| **图标** | `icon` / `图标` | Phone / URL / Rich Text | 可选展示图标字段 |

## 三、Lucent 初始化配置

1. **开启插件与权限**：在 Lucent 插件管理中确认 **Notion 书签收藏** 已启用，并开启以下权限：
   - **网络 (`network`)**：访问 Notion API 与抓取网页标题/简介。
   - **文件系统 (`filesystem`)**：写入本地缓存与 `search-index.json` 免前缀索引。
   - **剪贴板 (`clipboard`)**：用于一键收藏剪贴板中的网页链接。
2. **填写凭证并保存**：
   - **Notion Secret Token**：填入 `ntn_...` 或 `secret_...`（由本机 `0600` 保险箱加密托管，不以明文存储）。
   - **Notion Database ID / 数据库链接**：填入 32 位 ID 或完整 `notion.so` 数据库链接。
   - 可选参数：**新建默认标签**（默认 `书签`）、**自动抓取网页标题与简介**（默认开启）、**本地缓存有效期**（默认 `120` 秒，滑块 `0–3600s`）、**卡片最多展示条数**（`10` / `15` / `25`）。
3. **首次同步初始化**：
   - 保存配置后，按 `⌥Space` 输入 `bm refresh` 回车（或在插件列表点击「同步刷新 Notion 书签索引」），完成首次全量拉取与免前缀索引构建。

## 四、搜索框指令与快捷键用法

触发关键词为 `bm`（也可使用 `bookmark`、`notion`、`nav`）：

| 指令 | 说明 |
| :--- | :--- |
| `bm` | 打开书签列表；若剪贴板包含网址，顶部会显示「一键收藏剪贴板链接」与「新增书签」表单 |
| `bm github` | 按标题、链接、简介关键字过滤书签 |
| `bm #开发` | 按标签或分类筛选书签 |
| `bm add https://example.com` | 收藏链接并自动抓取网页标题与描述 |
| `bm add https://example.com 自定义标题 #工具 #AI` | 指定标题和标签收藏到 Notion |
| `bm add` | 直接收藏当前剪贴板中的链接 |
| `bm edit github title=GitHub主页 pin=true priority=20` | 修改匹配书签的字段 |
| `bm pin github` / `bm unpin github` | 置顶或取消置顶匹配书签 |
| `bm del github` | 将匹配书签归档（`archived: true`，可在 Notion 废纸篓恢复） |
| `bm refresh` | 强制忽略缓存，从 Notion 重新同步最新数据 |

> **子命令快捷键**：在插件设置中可为 **「收藏剪贴板链接到 Notion」**（`--add-clipboard`）、**「同步刷新 Notion 书签索引」**（`--refresh`）和 **「浏览全部 Notion 书签」**（`--list`）单独绑定全局快捷键；其中前两项支持后台静默执行。

## 五、常见报错排查与本地验证

- **`401` 错误**：Notion Token 填写有误或已过期，请在插件设置更新。
- **`404` 错误**：Database ID 有误，或尚未在 Notion 数据库页面右上角 `...` → **Connections** 中授权该 Integration。

```bash
printf '{"query":""}' | ./plugin-demo/notion-bookmarks/bin/notion-bookmarks
```
