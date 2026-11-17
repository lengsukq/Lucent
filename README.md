# 流光 Lumakey

> **交互式产品介绍页**：[https://lengsukq.github.io/Lumakey/](https://lengsukq.github.io/Lumakey/)（3D 体验主页）｜ [2D 图文详解与实验台](https://lengsukq.github.io/Lumakey/overview.html) ｜ **示例插件商店**：[`plugin-demo/`](plugin-demo/README.md) ｜ **工程文档**：[文档总览](docs/INDEX.md)

**专为 macOS Apple Silicon (`arm64`) 原生打造的轻量快捷效率中枢：菜单栏常驻、全局热键秒呼，以单一统一全搜栏整合应用、全盘文件、剪贴板、计算换算、物理鼠标平滑滚轮与 Plugin v3.6 原生一等公民插件系统（含自由 `WKWebView` 悬浮挂件、宿主统一 TCC 代理与内置 `lumakey-mcp` AI 造插件服务），并配备零 WebKit 的 Markdown/文本/图像/视频独立阅读窗口与自动内存回收架构。**

`Lumakey` 是一个完全独立、零第三方依赖的 Swift 6 + SwiftUI/AppKit 原生桌面应用（`app.lumakey.macos`），内置中英双语系统（首次打开自动跟随 macOS 系统语言，后续可在设置中心、菜单栏或 `⌥Space` 搜索指令中免重启实时切换「简体中文 / English」）以及「凝霜留白 (`Pure Frost`)」与「霓彩流光 (`Prism Pulse`)」双视觉主题。设计原则是：**优先复用 macOS 系统原生能力，保持干净可维护的分层模块化 Clean Code，让高频效率指令零延迟触达且空闲占用极低。**

## 核心能力

- **单一统一全搜快捷中枢 (`⌥Space`) + 零抖动恒定大圆角浮窗 (`880 × 544`)**：
  - 采用 AppKit `.popover` 自适应浅/深色 `9-slice NSVisualEffectView.maskImage` 严格裁剪连续曲率大圆角，禁用搜索框模糊透明混叠（`CrispSearchTextField` + 动态高对比文字/边框令牌），并配备中文输入法预编辑态守卫；
  - 主悬浮窗锁定 `880 × 544` 恒定尺寸，子过滤条内嵌左侧列表栏（主分割线不动、`Tab` 切换无动画），配合 `LauncherSelectionAnchor` 锚定选中项 ID，后台索引更新不打断当前选中位置；
  - **一个搜索栏搜遍一切**：基于前台活跃时长/频次 `log2` 加权、近度衰减与图钉常驻智能排序常用应用；默认开启 `全盘 + 外置盘` 索引作用域，单框同时支持汉字/多音字双音索引与拼音首字母、百分比/科学函数算式求值、10 维度中英单位与进制换算（含 CSS `px/rem/em/pt`、角度与速度）、本地路径/网址直达与 9 种网页搜索前缀、离线开发工具箱（时间戳/UUID/随机密码/Base64/URL/JWT/JSON/MD5/SHA-256/`#HEX` 色板/高清二维码）、快捷短语（`;` 前缀）、全盘文件（免前缀）、全格式富媒体剪贴板历史（支持 `↩` 直粘回原窗口、`⌥↩` 纯文本直粘、`⌘⌫` 删除、`⌘Z` 15 级撤回、`#RGB`/`rgb()`/`HSL` 复制、语音朗读及密码管理器/高危私钥过滤）以及插件与子功能直达。
- **Plugin v3.6 原生一等公民插件系统、自由画布浮窗 (`WKWebView` HUD)、宿主统一 TCC 代理与内置 `lumakey-mcp`**：
  - **自由窗口画布 + 原生融合双轨体验**：外部插件既可仅凭 `plugin.json` 输出轻量 JSON 渲染默认卡片与**独立置顶实时悬浮面板 (`lumakey://panel/<id>`)**，也可通过 `window` / `floatingWindow` 权限开启**不限 UI 样式的 `WKWebView` 自由窗口或无边框透明置顶挂件 (`lumakey://window/<id>` + `window.lumakey` 双向 JS SDK)**；所有涉及屏幕录制、辅助功能（划词读取/原窗口粘贴回填）与系统通知的底层 TCC 权限均由宿主统一代申并按插件粒度隔离分发；
  - **内置 `lumakey-mcp` (12 项 MCP 工具)**：支持通过标准 stdio JSON-RPC 2.0 对接 Claude Code、Cursor、Codex、Gemini CLI 等 AI Agent，设置页内置一键生成整套双语接入提示词，写完即刻经 `FSEvents` 350ms 热重载生效；
  - **自定义商店智能入驻 + [8 款官方旗舰插件 (`plugin-demo/`)](plugin-demo/README.md)**：「精选市场」顶部统一智能地址栏支持一键识别自定义插件商店 (`lumakey-registry.json`) 或独立插件，内置 `ai-quota`（Codex/Claude Code/agy/dsh 实时额度与 DeepSeek 余额面板）、`browser-hub`（三端浏览器书签/历史 0ms 全搜）、`lumalink-companion`（LumaLink 多屏远控/RDP/防窥）、`notion-bookmarks`、`translate-hub`（划词/OCR 多源译站与 Anki 导出）、`mac-pilot`（系统控制/16 项设置直达/访达助手）、`quick-remind`（自然语言倒计时/原生提醒事项）与 `screen-shield`（多屏全屏状态屏清洁/防误触遮罩），支持 SHA-256 与权限防伪装核验及无损版本升级；
  - **系统级沙箱与端到端加密备份**：外部脚本运行期由 `PluginSandboxProfileBuilder`（`/usr/bin/sandbox-exec` Seatbelt 策略）与纯净环境变量白名单强制隔离网络、磁盘写与子进程作用域，采用双轨 256-bit CSPRNG 主密钥 `AES-GCM` 保险箱（`LMKYVLT2`）密封密钥；全部 10 项核心快捷键与插件热键支持三层冲突检测；支持带顶层 `SHA-256` 校验与 `LZFSE` 压缩的 `.lumakeybackup` v2 归档（含 `PluginData`、外部路径文件、可选加密口令迁移密钥及本地恢复前防呆快照），并支持原生 RFC 4918 WebDAV 云同步。
- **内置系统脉搏监控悬浮窗 (`⌥M`)、多视图文件工作台 (`⌥E`) 与流光随行 (`LumaLink`)**：
  - 基于 Darwin Mach、`IOKit` 与 `getifaddrs` 零子进程采样 CPU P/E 核负载、动态等效频率 (`GHz`)、GPU 利用率、内存/Swap、实时整机功耗 (`W`) 与网速（新装默认关闭）；宿主 `systemControl` 桥接支持多屏全屏状态屏遮罩与键鼠防误触拦截；
  - 按需文件工作台 (`⌥E`) 支持单双栏自适应并排、`⌘`/区间多选与液态蓝矩形框选、跨目录拖拽与复制粘贴、新建文件夹、单文件改名与批量重命名预检、系统废纸篓安全删除、6 种排序、7 类媒体筛选、右侧居中图文视频预览与只读 NTFS 护航。
- **跨多显示器截图标注、独立窗口无遮挡捕获、流式区域 GIF 录制与极速识字引擎 (`⌥A` / `⌥G` / `⌥O`)**：
  - 基于 `ScreenCaptureKit`、`MultiDisplayLayout` 与 `ScreenTopologyAndWindowMatcher` 实现多屏逐屏原生 `backingScaleFactor` 独立 DPI 分片冻屏（完整支持负坐标左/下副屏、纵向堆叠及 `1x`/`2x` 混合屏拓扑）、跨显示器无缝框选与前后 Z 序重叠窗口切换（`Tab`），并配备显示器热插拔守护；单击应用窗口支持 `SCContentFilter(desktopIndependentWindow:)` 无遮挡独立捕获（保留原生透明圆角，支持 `⌥` 单击/工具栏一键去阴影）；
  - 支持 `R` 键恢复上次选区、8 控制点缩放、放大镜取色（`C` 复制 `#HEX` / `⇧C` 复制 `rgb()`）、实时马赛克预览、方向键 `1pt`/`⇧+10pt` 微调、**矩形 / 椭圆 / 箭头 / 直线 / 画笔 / 荧光笔 / 马赛克 / 聚光灯 / 序号 / 文字** 共 10 种标注工具（数字键 `1–0` 秒切）、`⌘Z` 撤销 / `⇧⌘Z` 重做、`P` 钉图 / `O` 识字、`⌘S` 保存与双击复制；PNG 落盘注入显示器真实 DPI 元数据确保 1:1 Retina 逻辑尺寸还原；
  - **原生流式区域 GIF 录制 (`⌥G`)**：基于 `ScreenCaptureKit` (`SCStream`) + `VideoToolbox` + `ImageIO` 实现单屏/单窗口零拷贝硬件流式 GIF89a 采集与跨屏分片拼接录制（配套 `sharingType = .none` 非侵入穿透边界提示框），配备灵动岛悬浮控制条、640p/960p/HD 缩放与静止帧合并压缩；
  - **交互式悬浮钉图 & 亚秒级离线 Vision OCR**：支持全图拖动、滚轮缩放、`⌥+滚轮` 透明度调节、`T` 键半透明穿透对照与「发送到扩展插件」，框选松手即自动识字并居中弹出独立识字结果窗。
- **内置物理鼠标平滑滚动与滚轮方向增强**：
  - 基于 `CGEvent.tapCreate` 精准区分物理鼠标滚轮（`scrollWheelEventIsContinuous == 0`），**完全保留触控板自然滚动**；支持滚轮方向反转、120Hz 高帧率像素级平滑插值、`⇧` 横向滚动、`⌥` 3× 加速与应用 Bundle ID 排除列表；关闭或静止时 0 后台消耗。
- **独立销毁型 Markdown / 文本 / 图像 / 视频窗口**：
  - **网络流量与去向监控 (`⌥N`) & 应用缓存管理**：无需 Root 权限实时展示进程级上下行速率、累计流量与远端去向；配套独立应用缓存管理页，按桶统计并安全清理临时缓存；
  - **独立窗口阅读、置顶 & 4K 影院播放器**：纯 Swift `MarkdownDocumentParser` 零 `WKWebView` 渲染，通过序列化 `Hev1ResourceLoader` 原生硬解 `'hev1'` 4K HEVC MP4，支持同目录播放列表连播、小窗浮层与外部播放器打开。
- **智能程序坞 (Dock) 驻留 & 标准分发公证流水线**：
  - 打开独立窗口时自动在程序坞显示图标，关闭所有标准窗口后自动恢复轻量菜单栏驻留；
  - 支持本地 TCC 稳定开发签名（`scripts/setup-local-signing.sh`）以及面向对外分发的 `Hardened Runtime` + `Developer ID Application` + Apple `notarytool` / `stapler` 一键公证装订流水线（`scripts/release-macos.sh`）。
- **最优内存与子进程自洁架构 (`ProcessSupervisor` & `MemoryStats`)**：
  - 全部外部子进程通过 `ProcessSupervisor` 托管（8s 超时强杀 + 有界读取 + 隐藏/退出即清理）；浮窗隐藏 `30s` 自动销毁视图树，文件索引采用带 `SHA-256` 校验的 `LMKYIDX3` `mmap` 快照并在空闲 `90s` 或收到内存压力告警时自动卸载归还堆页。

## 明确的产品界限

- **以快捷工具为核心，文件管理作为按需附加工具**：主入口是快捷键唤起的悬浮控制面板，不强制打开占满屏幕的大窗口。
- **不做图像编辑与视频剪辑**：仅提供无损只读看图与高效视频播放。
- **不做常驻后台全盘数据库守护进程**：不部署 `launchd` 常驻后台建库服务，索引仅按需驻留并在空闲时自动卸载。
- **只支持 Apple Silicon (`arm64`) / macOS 14+**：构建与校验脚本显式拒绝 `x86_64` 与 Rosetta 转译环境。

## 快速开始

```bash
# 1. 文档与链接自检
python3 -B scripts/check-docs.py

# 2. 标准 Swift Testing 单元测试与性能延迟基准
swift test --arch arm64

# 3. 模块单向依赖边界、Clean Code（<=300行/文件）、编译与 MCP 真实子进程联调校验
bash scripts/verify-macos.sh

# 4. 本地构建独立 macOS arm64 .app 产物 (dist/Lumakey.app)
bash scripts/build-macos.sh

# 5. 打包 dist/Lumakey.dmg 并同步安装到本机 /Applications/Lumakey.app
bash scripts/install-macos.sh

# 6. 构建面向他人的公开发行版（自动启用 Hardened Runtime，支持 Developer ID 签名与 Apple 公证装订）
# APPLE_NOTARY_PROFILE="lumakey-notary" bash scripts/release-macos.sh
bash scripts/release-macos.sh
```

更多说明请从 [文档总览](docs/INDEX.md) 开始，参与共建请参阅 [贡献指南](CONTRIBUTING.md)。

## 开源许可

本项目采用 [MIT License](LICENSE) 开源发布。
