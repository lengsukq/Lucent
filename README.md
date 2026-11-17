# 流光 Lumakey

> **交互式产品介绍页**：[https://lengsukq.github.io/Lumakey/](https://lengsukq.github.io/Lumakey/)（3D 体验主页）｜ [2D 图文详解与实验台](https://lengsukq.github.io/Lumakey/overview.html) ｜ **示例插件商店**：[`plugin-demo/`](plugin-demo/README.md) ｜ **工程文档**：[文档总览](docs/INDEX.md)

**一触流光，用完即焚 —— 专为 macOS Apple Silicon (`arm64`) 打造的零第三方依赖 Swift 6 原生效率中枢与 AI 插件平台。**

`Lumakey`（`app.lumakey.macos`）驻留于菜单栏、以全局热键毫秒呼出。我们不试图把用户塞进一座臃肿的全家桶大窗，而是打磨一块**极度克制、原生高速、用完即焚**的微内核底座，把高频的系统能力做到零抖动直达，把长尾与个性化工作流通过 **Plugin v3.6** 与内置 **`lumakey-mcp`** 完整交还给你。

---

## 核心产品思想

1. **底座极度克制，边界无限生长**
   核心只保留系统级高频刚需（全搜、剪贴板、多屏截图标注/录屏/OCR、物理鼠标平滑、独立阅读/看图/影院窗与按需工作台），个性化场景交由 **Plugin v3.6** 一等公民生态按需生长。**未安装或已停用的插件零内存、零轮询、零界面打扰**；一旦启用，即享有与内置能力完全平权的全局搜索、子命令热键、上下文联动与设置体验。
2. **一触流光，用完即焚（自洁内存架构）**
   所有悬浮窗、监控读数与快捷按钮在**新装时默认全关**，只在你需要时唤醒，离开后自动释放：
   - 主悬浮面板隐藏 `30s` 自动销毁视图树；
   - `LMKYIDX3` 全盘 `mmap` 索引空闲 `90s` 或收到系统内存压力信号即刻卸载堆页（冷启动仅读 4 KB 头部 O(1) 探测）；
   - Markdown 阅读窗、只读看图窗、4K 影院与外部插件自由窗口/悬浮面板在关窗瞬间置空视图并终止轮询任务；
   - 全部外部脚本由 `ProcessSupervisor` 托管（默认 `8s` 超时强杀、双管道无死锁排空与关闭即精确取消）。
3. **恒定几何与确定性肌肉记忆**
   主面板严格锁定 **`880 × 544`** 恒定尺寸，内嵌子过滤条切换分类时外框与主分割线绝对静止；配合 `LauncherSelectionAnchor` 锚定选中项 ID，后台异步索引刷新绝不抢夺焦点；支持中文输入法预编辑态守卫、`⌘1..9` 快选、`↩` / `⌥↩` 直粘回原窗口、`⌘C` 复制与 `⌘Return` 次级动作，让每一次呼出都形成稳定的键盘肌肉记忆。
4. **Native Services First，零第三方包依赖**
   全仓**零第三方 SwiftPM / CocoaPods 依赖**，拒绝跨平台套壳与重型运行时，直接驱动 macOS 14+ 与 Apple Silicon 原生系统框架（`ScreenCaptureKit`、`SCStream` + `VideoToolbox`、`Vision`、`AVKit`、`Darwin Mach`/`IOKit`、`Carbon`、`CGEventTap`、`FSEvents`、`Compression LZFSE`、`CryptoKit`、`sandbox-exec`）。
5. **双轨安全模型与开放 AI 共创**
   - **「macOS 认宿主，宿主审插件」**：外部插件不直接向系统索取高危 TCC 权限，涉及辅助功能（划词读取/粘贴回填）、屏幕录制与系统通知均由签名宿主 `Lumakey.app` 统一代申并按插件粒度隔离分发；
   - **最小权限 + OS 级隔离**：脚本运行期受 `PluginSandboxProfileBuilder`（Seatbelt）与纯净环境变量白名单约束，敏感密钥密封于双轨 256-bit CSPRNG + `AES-GCM` 加密保险箱（`LMKYVLT2`）；
   - **一句话十秒造插件**：内置 12 项工具的原生 stdio `lumakey-mcp` 服务器让 Claude Code、Cursor、Codex、Gemini CLI 直接在本地生成、审计、实测并通过 `FSEvents` 350ms 热重载生效。

---

## 设计哲学与视觉体验

- **AppKit 真圆角穿透毛玻璃**：以 `NSVisualEffectView`（`.popover` + 9-slice `28pt` 连续曲率 `maskImage`）彻底消除方角渗漏，搜索栏采用禁用透明模糊混叠的 `CrispSearchTextField`，并严格遵守 Apple `.continuous` 同心圆角层级（`28pt` → `24pt` → `22pt` → `18pt` → `14pt` → `12pt`）。
- **双生液态玻璃主题 & 免重启中英双语**：
  - **凝霜留白 (`Pure Frost`)**：零色晕、高对比 Studio 级浅色瓷感；
  - **霓彩流光 (`Prism Pulse`)**：棱镜高光与深邃光谱暗色玻璃；
  - 首次打开自动跟随 macOS 语言，支持在设置中心、菜单栏或搜索栏免重启切换「简体中文 / English」与双主题，并自动同步响应 macOS「减少透明度 / 增强对比度」无障碍选项，同时实时透传给外部插件。
- **智能程序坞 (Dock) 驻留**：平时仅以轻量 `LSUIElement` 驻留菜单栏，打开标准独立窗口时自动在程序坞显现图标，关窗后自动恢复轻量静默。

---

## 核心能力全景

- **单一统一全搜快捷中枢 (`⌥Space`)**：
  - 基于前台活跃时长/频次 `log2` 加权、近度衰减与图钉常驻排序常用应用；支持汉字/多音字双音索引与拼音首字母；
  - 默认开启 `全盘 + 外置盘` 免前缀极速检索（`LMKYIDX3` `mmap` 快照 + `FSEvents` 增量同步），同时内聚百分比/科学函数算式求值、10 维度中英单位与进制换算（含 CSS `px/rem/em/pt`、角度与速度）、本地路径/网址直达与 9 种网页搜索前缀、离线开发工具箱（时间戳/UUID/随机密码/Base64/URL/JWT/JSON/MD5/SHA-256/`#HEX` 色板/高清二维码）、`;` 快捷短语、全格式富媒体剪贴板历史（`↩` 原窗直粘、`⌥↩` 纯文本直粘、`⌘⌫` 删除、`⌘Z` 15 级撤回、`#RGB`/`rgb()`/`HSL` 复制、语音朗读及密码管理器/高危私钥过滤）与插件子功能直达。
- **Plugin v3.6 双轨插件生态、自由画布 HUD 与官方商店 (`plugin-demo/`)**：
  - **双轨呈现**：既可仅凭 `plugin.json` 输出轻量 JSON 渲染默认卡片与**独立置顶实时悬浮面板 (`lumakey://panel/<id>`)**，也可通过 `window` / `floatingWindow` 开启**不限 UI 样式的 `WKWebView` 自由窗口或无边框透明置顶挂件 (`lumakey://window/<id>` + `window.lumakey` 双向 JS SDK)**；
  - **自定义商店智能入驻 + [8 款官方旗舰插件 (`plugin-demo/`)](plugin-demo/README.md)**：「精选市场」顶部统一智能地址栏自动识别仓库、商店清单（`lumakey-registry.json`）或 `.zip` 包，提供 `SHA-256` 与权限防伪装核验及无损升级。官方商店内置 `ai-quota`（Codex/Claude Code/agy/dsh 实时额度自由挂件与 DeepSeek 余额）、`browser-hub`（三端浏览器书签/历史 0ms 全搜）、`lumalink-companion`（LumaLink 多屏远控/RDP/防窥）、`notion-bookmarks`、`translate-hub`（划词/OCR 多源译站与 Anki 导出）、`mac-pilot`（系统控制/16 项设置直达/访达助手）、`quick-remind`（自然语言倒计时/原生提醒事项/系统通知）与 `screen-shield`（多屏全屏状态屏遮罩）。
- **多显示器原生 DPI 截图标注、流式 GIF 录制与离线 OCR (`⌥A` / `⌥G` / `⌥O`)**：
  - 基于 `ScreenCaptureKit`、`MultiDisplayLayout` 与 `ScreenTopologyAndWindowMatcher` 实现逐屏原生 `backingScaleFactor` 独立 DPI 分片冻屏（支持负坐标副屏、纵向堆叠、`1x`/`2x` 混合屏与热插拔守护）、`Tab` 前后 Z 序窗口切换与 `SCContentFilter(desktopIndependentWindow:)` 无遮挡独立窗口捕获（可选去阴影）；
  - 内置 `R` 恢复上次选区、放大镜取色（`C` 复制 `#HEX` / `⇧C` 复制 `rgb()`）、10 种标注工具（`1–0` 秒切）、`⌘Z`/`⇧⌘Z` 撤销重做、PNG 真实 DPI 写入与 1:1 悬浮钉图（`T` 键半透明穿透对照与「发送到扩展插件」）；
  - **原生流式区域 GIF 录制 (`⌥G`)**：`SCStream` + `VideoToolbox` + `ImageIO` 硬件流式采集与跨屏分片裁剪（配套 `sharingType = .none` 穿透边界框），支持灵动岛 HUD、640p/960p/HD 缩放与静止帧合并；
  - **亚秒级离线 Vision OCR**：绑定 CPU 阶段避开 ANE 卡顿，框选松手即自动识别中英文字与条码并弹出独立结果窗。
- **按需独立工具与系统原生增强**：
  - **物理鼠标 120Hz 平滑滚轮 & 方向反转**：通过 `CGEvent.tapCreate` 区分 `scrollWheelEventIsContinuous == 0`，**完全保留触控板自然滚动**，支持 `⇧` 横向、`⌥` 3× 加速与应用排除列表，静止 0 功耗；
  - **系统脉搏 (`⌥M`) & 网络去向 (`⌥N`) & 应用缓存管理**：Darwin Mach/`IOKit` 采样 CPU P/E 核负载、频率 (`GHz`)、GPU、内存/Swap 与整机功耗 (`W`)；免提权实时监控进程上下行速率与远端去向；分桶盘点并清理应用缓存；
  - **文件工作台 (`⌥E`) & 零 WebKit 阅读/4K 影院窗**：按需开启单双栏文件管理（`⌘`/区间多选、矩形框选、拖拽互传、批量重命名预检、废纸篓安全删除与只读 NTFS 护航）；纯 Swift `MarkdownDocumentParser` 阅读窗与序列化 `Hev1ResourceLoader` 硬解 `'hev1'` 4K HEVC 影院窗。
- **安全治理、三层热键冲突检测与 `.lumakeybackup` v2 云备份**：
  - 全部 10 项核心热键与插件子功能热键支持可视化录制与三层冲突检测（应用内/系统符号热键/Carbon 占用）；
  - 支持带顶层 `SHA-256` 校验与 `LZFSE` 压缩的 `.lumakeybackup` v2 归档（含 `PluginData`、外部路径文件、可选口令端到端加密迁移密钥与恢复前本地防呆快照），并原生直连 RFC 4918 WebDAV 云同步。

---

## 明确的产品界限（我们坚持“不做”的事）

- **不做重型全屏桌面总管**：主入口永远是快捷键秒呼的悬浮快捷中枢，双栏文件管理仅作为按需唤起、关闭即释放的附加工具。
- **不在内置阅读器引入 WebKit**：内置 Markdown/文本/图片/视频独立窗口严格零 `WKWebView`（仅外部插件显式申请并获授权 `window`/`floatingWindow` 时按需宿主托管，关窗即毁）。
- **不做图像编辑与视频剪辑**：仅提供无损只读看图、轻量截图标注/GIF 录制与高效硬解播放。
- **不做常驻后台全盘数据库守护进程**：不部署 `launchd` 后台建库服务，索引仅按需驻留并在空闲时自动卸载。
- **只聚焦 Apple Silicon (`arm64`) / macOS 14+**：构建与校验门禁显式拒绝 `x86_64` 与 Rosetta 转译，彻底告别历史架构包袱。

---

## 模块架构与快速开始

工程拆分为九个单向无环（DAG）Swift 6 目标（`LumakeyFoundation` → `LumakeySearch` / `LumakeySystem` / `LumakeyMedia` → `LumakeyCore` → `Lumakey` / `lumakey-mcp` + `LumakeyTests` / `LumakeyCheck`），并由校验门禁自动审计反向导入与**单文件 `<= 300` 行** Clean Code 红线（详见 [系统架构与 Clean Code 约束](docs/ARCHITECTURE.md)）。

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

更多设计与开发指南请从 [文档总览](docs/INDEX.md) 开始，参与共建请参阅 [贡献指南](CONTRIBUTING.md)。

## 开源许可

本项目采用 [MIT License](LICENSE) 开源发布。
