# 流光 Lumakey

**专为 macOS Apple Silicon (`arm64`) 原生打造的轻量快捷效率中枢：菜单栏常驻、全局热键秒呼，以单一统一全搜栏整合应用、全盘文件、剪贴板、计算换算、物理鼠标平滑滚轮与深度融合插件系统，并配备零 WebKit 的 Markdown/文本/图像/视频独立阅读窗口与自动内存回收架构。**

`Lumakey` 是一个完全独立、零第三方依赖的 Swift 6 + SwiftUI/AppKit 原生桌面应用（`app.lumakey.macos`），内置中英双语系统（首次打开自动跟随 macOS 系统语言，后续可在设置中心、菜单栏或 `⌥Space` 搜索指令中免重启实时切换「简体中文 / English」）以及「凝霜留白 (`Pure Frost`)」与「霓彩流光 (`Prism Pulse`)」双视觉主题。设计原则是：**优先复用 macOS 系统原生能力，保持干净可维护的分层模块化 Clean Code，让高频效率指令零延迟触达且空闲占用极低。**

## 核心能力

- **单一统一全搜快捷中枢 (`⌥Space`) + 零抖动零动画切换 (`880 × 544` 恒定真圆角悬浮窗 + 高对比自适应排版)**：
  - 采用 AppKit `.popover` 自适应浅/深色 `9-slice NSVisualEffectView.maskImage` 严格裁剪连续曲率大圆角，禁用搜索框模糊透明混叠（`CrispSearchTextField` + 动态高对比文字/边框令牌），保证浅色与深色壁纸下文字同样锐利清晰；
  - 主悬浮窗锁定 `880 × 544` 恒定尺寸，并将子过滤条移入左侧列表栏内部（主分割线不动、`Tab` 切换无动画），配合 `LauncherSelectionAnchor` 锚定选中项 ID，后台索引更新不会打断当前选中位置；
  - **一个搜索栏搜遍一切**：基于前台活跃时长/频次 `log2` 加权、近度衰减与图钉常驻智能排序常用应用；默认即开启 `全盘 + 外置盘` 索引作用域，单框同时支持汉字/拼音、算式/进制/单位换算、离线开发工具箱（时间戳/UUID/随机密码/Base64/URL/JWT/JSON/MD5/SHA-256/`#HEX` 色板/高清二维码）、快捷短语（`;` 前缀）、端口占用、全盘文件（免前缀）、剪贴板历史以及插件与插件子功能直达。
- **深度融合插件系统 v3、系统级 Seatbelt 沙箱隔离、自定义商店智能入驻、本地备份 & 原生 WebDAV 云同步**：
  - 「精选市场」内置单一智能地址框，粘贴任意 HTTPS 地址或 GitHub 仓库即可自动识别为**自定义插件商店 (`lumakey-registry.json`)** 或**单个外部插件**，支持多商店订阅切换、SHA-256 与权限防伪装核验及无损版本升级；
  - 外部脚本运行期由 `PluginSandboxProfileBuilder`（`/usr/bin/sandbox-exec` Seatbelt 策略）与纯净环境变量白名单强制管控网络、磁盘写与外部子进程作用域，并采用双轨 256-bit 随机主密钥 `AES-GCM` 保险箱（`LMKYVLT2`）加密保护插件密钥；
  - 全部 10 项核心快捷键与外部插件热键支持可视化按键录制与三层冲突检测（应用内/插件互斥、系统符号热键与 `Carbon` 外部占用探测）；
  - 支持打包带顶层 SHA-256 完整性校验的 `.lumakeybackup` 归档（含主题、配置、自定义插件与已收藏剪贴板条目），并通过原生 RFC 4918 WebDAV 同步至云盘或私有 NAS。
- **内置系统脉搏监控悬浮窗 (`⌥M`) & 多视图文件与外置磁盘工作台 (`⌥E`)**：
  - 基于 Darwin Mach、`IOKit` 与 `getifaddrs` 零子进程采样 CPU P/E 核负载、动态等效频率 (`GHz`)、GPU 利用率、内存/Swap、实时整机功耗 (`W`) 与网速（新装默认关闭）；
  - 按需工作台 (`⌥E`) 支持单双栏自适应并排、`⌘`/区间多选与矩形拖动框选、跨目录拖拽与复制粘贴、新建文件夹、单文件改名与批量重命名预检、系统废纸篓安全删除、6 种排序、7 类媒体筛选、右侧居中图文视频预览与只读 NTFS 护航。
- **智能选区截图标注、零依赖区域 GIF 动图录制与极速识字引擎 (`⌥A` / `⌥G` / `⌥O`)**：
  - 基于 `ScreenCaptureKit` 实现毫秒级冻屏：支持窗口吸附、`R` 键恢复上次选区、8 控制点缩放、放大镜取色（`C` 复制 `#HEX` / `⇧C` 复制 `rgb()`）、实时马赛克预览、自动聚焦文字批注、右键重选/退出，以及 **矩形 / 椭圆 / 箭头 / 直线 / 画笔 / 荧光笔 / 马赛克 / 聚光灯 / 序号 / 文字** 共 10 种标注工具（数字键 `1–0` 秒切）、`⌘Z` 撤销 / `⇧⌘Z` 重做、`⌘S` 保存与双击复制；
  - **原生区域 GIF 录制 (`⌥G`)**：复用 `ScreenCaptureKit` (`SCScreenshotManager`) + `ImageIO` 流式 GIF89a 编码，配备悬浮录制控制条、640p/960p/HD 分辨率缩放与静止帧合并压缩；
  - **交互式悬浮钉图 & 亚秒级离线 Vision OCR**：支持全图拖动、滚轮缩放、`⌥+滚轮` 透明度调节与右键菜单，框选松手即自动识字并弹出独立识字结果窗。
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
