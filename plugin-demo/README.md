# Lumakey 官方插件商店与扩展示例 (`plugin-demo`)

本目录既是仓库自带的**完整自定义插件商店示例（含 `lumakey-registry.json` 与 `dist/*.zip` 校验归档包）**，也是面向 **Lumakey Plugin v3** 架构的八款旗舰外置插件源码：

- [`ai-quota/`](ai-quota/README.md)：**AI 额度雷达 · CLI 用量与 API 余额面板**（并发调用本机安装的 `codex`、`claude`、`agy`、`dsh` CLI 与会话日志实时展示 5h/7d 速率窗口余量、重置倒计时与今日 Token，并支持在 `LMKYVLT2` 加密保险箱写入 `DeepSeek API Key` 查询 CNY/USD 账户余额）。
- [`browser-hub/`](browser-hub/README.md)：**三端浏览器书签与历史中枢**（本地文件与 SQLite WAL 无锁直连 Microsoft Edge、Google Chrome 多 Profile 与 Apple Safari 书签、阅读列表及历史记录，自动同步 `⌥Space` 免前缀索引并支持按来源浏览器打开）。
- [`lumalink-companion/`](lumalink-companion/README.md)：**流光随行 · LumaLink 远控伴侣**（纯外部沙盒 `resourceScopes: []` + 受控宿主桥接 `capabilities: ["lumaLinkStatus"]` 全功能远控台，支持置顶配对二维码、多屏 HiDPI 切换、防窥黑屏、防休眠与设备解绑）。
- [`notion-bookmarks/`](notion-bookmarks/README.md)：**Notion 书签收藏插件**（云端 REST API + 本地免前缀检索索引示例，声明 `capabilities: ["clipboard"]`、`resourceScopes: ["network", "filesystem"]`）。
- [`translate-hub/`](translate-hub/README.md)：**流光译站 · 划词/截图多源翻译与生词本**（联动 `selection`、`ocr`、`audio`、`clipboard` 桥接，支持跨应用划词即译、截图离线识字翻译、免配置词典与本地 Ollama 并行、原声朗读及导出 Anki `.tsv` / `.csv` 生词卡片）。
- [`mac-pilot/`](mac-pilot/README.md)：**桌面中控台 · 系统控制、设置直达与访达助手**（支持音量档位/静音切换、防休眠常亮、16 项 macOS 系统设置分栏免前缀秒达、访达当前目录防重名新建文件与外置磁盘一键安全推出）。
- [`quick-remind/`](quick-remind/README.md)：**闪电提醒 · 一句话倒计时与提醒看板**（解析 `10m 喝水`、`18:30 拿快递`、`明天 9:00 周报 工作日` 等自然短语，零常驻守护同步 macOS 原生提醒事项准点弹窗，支持推迟 Snooze 与语音播报）。
- [`screen-shield/`](screen-shield/README.md)：**状态屏 · 清洁屏幕与暂离防误触遮罩**（一键盖住全部显示器展示「清洁屏幕」「请勿触碰」「马上回来」或自定义告示，联动拦截键盘与滚轮误触，长按 `Esc` 2 秒安全退出）。

## 快速使用

### 方式一：作为插件商店一键入驻（推荐）

1. 打开 **Lumakey → 设置 → 插件中心 → 精选市场**。
2. 在顶部「**智能入驻 / 直装地址**」输入框粘贴本目录的本地路径（如 `/Volumes/lightlsle/Code/Lumakey/plugin-demo`）或远端仓库的 `/tree/main/plugin-demo` 子目录地址，点击 **「识别」**。
3. 自动入驻 **「Lumakey 官方示例商店 (plugin-demo)」** 后，即可在商店列表中带 `SHA-256` 校验一键安装任意官方插件。

### 方式二：命令行安装到本地插件目录

```bash
# 安装全部八款商店插件
bash plugin-demo/install.sh

# 或单独安装指定插件（如 ai-quota / translate-hub / screen-shield / mac-pilot / quick-remind）
bash plugin-demo/install.sh ai-quota
```

### 方式三：重新打包商店归档与 `lumakey-registry.json`

修改插件源码后，执行以下命令即可调用 `lumakey-mcp` 自动完成 v3 校验、生成 `dist/*.zip` 并更新 `lumakey-registry.json` 中的 64 位 `SHA-256`：

```bash
bash plugin-demo/package-store.sh
```
