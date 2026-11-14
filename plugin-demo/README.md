# Lumakey 官方插件示例 (`plugin-demo`)

本目录存放面向 **Lumakey Plugin v3** 架构的官方外置插件示例，演示如何在「零常驻守护进程、零第三方依赖、显式声明 `capabilities`」原则下，结合 `mode: "view"` 液态玻璃卡片与 `commandArgs` 交互闭环构建实用效率扩展。

## 包含示例

- [`notion-bookmarks/`](notion-bookmarks/README.md)：**Notion 书签收藏插件**
  - 参考开源项目 [`lengsukq/nav-notion-lime`](https://github.com/lengsukq/nav-notion-lime) 的 Notion 数据库字段模型、网页元信息抓取（Title / Description）及增删改查逻辑。
  - 纯沙盒运行（`"capabilities": []`），无需申请宿主 TCC 权限，直接调用 macOS 内置 `/usr/bin/python3` 与标准库访问 Notion API。

## 快速使用

### 方式一：在 Lumakey 界面导入（推荐）

1. 打开 **Lumakey → 设置 → 插件中心**。
2. 点击「**导入插件目录**」，选择本仓库下的 `plugin-demo/notion-bookmarks` 文件夹。
3. 在右侧参数表单填入 **Notion Secret Token** 与 **Notion Database ID**，点击「**保存配置**」。
4. 呼出 `⌥Space`，输入 `bm`（或 `bookmark` / `notion` / `nav`）即可检索、一键收藏剪贴板链接、置顶或归档书签。

### 方式二：一键安装到本地插件目录

```bash
bash plugin-demo/install.sh
```

脚本会将 `plugin-demo/notion-bookmarks` 复制到 `~/Library/Application Support/Lumakey/Plugins/notion-bookmarks` 并赋予 `run.sh` 可执行权限，Lumakey 将通过 `FSEvents` 在 350ms 内自动热重载。

### 方式三：使用 `lumakey-mcp` 本地校验与联调

```bash
swift build -c debug --arch arm64 --product lumakey-mcp
BIN_DIR="$(swift build -c debug --arch arm64 --show-bin-path)"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lumakey_validate_plugin","arguments":{"id":"notion-bookmarks"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lumakey_run_plugin_test","arguments":{"id":"notion-bookmarks","query":"","clipboardText":"https://github.com/lengsukq/Lumakey"}}}' \
  | "$BIN_DIR/lumakey-mcp" --plugins-dir ./plugin-demo
```
