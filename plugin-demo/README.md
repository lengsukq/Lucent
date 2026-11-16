# Lumakey 官方插件商店与扩展示例 (`plugin-demo`)

本目录既是仓库自带的**完整自定义插件商店示例（含 `lumakey-registry.json` 与 `dist/*.zip` 校验归档包）**，也是面向 **Lumakey Plugin v3** 架构的三款旗舰外置插件源码：

- [`browser-hub/`](browser-hub/README.md)：**三端浏览器书签与历史中枢**（本地文件与 SQLite WAL 无锁直连 Microsoft Edge、Google Chrome 多 Profile 与 Apple Safari 书签、阅读列表及历史记录，自动同步 `⌥Space` 免前缀索引并支持按来源浏览器打开）。
- [`lumalink-companion/`](lumalink-companion/README.md)：**流光随行 · LumaLink 远控伴侣**（纯外部沙盒 `resourceScopes: []` + 受控宿主桥接 `capabilities: ["lumaLinkStatus"]` 全功能远控台，支持置顶配对二维码、多屏 HiDPI 切换、防窥黑屏、防休眠与设备解绑）。
- [`notion-bookmarks/`](notion-bookmarks/README.md)：**Notion 书签收藏插件**（云端 REST API + 本地免前缀检索索引示例，声明 `capabilities: ["clipboard"]`、`resourceScopes: ["network", "filesystem"]`）。

## 快速使用

### 方式一：作为插件商店一键入驻（推荐）

1. 打开 **Lumakey → 设置 → 插件中心 → 精选市场**。
2. 在顶部「**智能入驻 / 直装地址**」输入框粘贴本目录的本地路径（如 `/Volumes/lightlsle/Code/Lumakey/plugin-demo`）或远端仓库的 `/tree/main/plugin-demo` 子目录地址，点击 **「识别」**。
3. 自动入驻 **「Lumakey 官方示例商店 (plugin-demo)」** 后，即可在商店列表中带 `SHA-256` 校验一键安装 `三端浏览器书签与历史中枢`、`流光随行 · LumaLink 远控伴侣` 或 `Notion 书签收藏`。

### 方式二：命令行安装到本地插件目录

```bash
# 安装全部三款商店插件（browser-hub + lumalink-companion + notion-bookmarks）
bash plugin-demo/install.sh

# 或单独安装三端浏览器书签与历史中枢
bash plugin-demo/install.sh browser-hub
```

### 方式三：重新打包商店归档与 `lumakey-registry.json`

修改插件源码后，执行以下命令即可调用 `lumakey-mcp` 自动完成 v3 校验、生成 `dist/*.zip` 并更新 `lumakey-registry.json` 中的 64 位 `SHA-256`：

```bash
bash plugin-demo/package-store.sh
```
