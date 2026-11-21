# 当前实现状态

本文件仅记录当前仓库中已通过编译、单测与集成校验的**真实当前能力**（遵循单一事实来源原则，不堆叠历史版本流水账）；后续演进规划见 [版本路线图](ROADMAP.md)。

## 1. 核心架构与工程门禁

- **纯原生 Swift 6 无环模块分层**：全仓采用 `macOS 14.0+` / `arm64` 编译（`.swiftLanguageMode(.v6)`），**零第三方依赖**，划分为 `LucentFoundation` → `LucentSearch` / `LucentMedia` / `LucentSystem` → `LucentCore` → `Lucent` / `lucent-mcp` 单向无环（DAG）架构，由 `scripts/verify-macos.sh` 静态拦截越界反向导入与单文件 `≤ 300` 行上限。
- **双生液态玻璃与实时双语**：内置「晴霜浅色 (`Light Frost`)」与「曜石暗色 (`Obsidian Dark`)」两套原生 macOS 液态折射毛玻璃主题（支持跟随系统深浅色外观与 `NSApp.appearance` KVO 联动、统一大圆角双层镜面高光与专属光学点击波纹/物理弹簧回弹），配合简体中文 / English 免重启全局热切换；品牌视觉由 `LucentFoundation.BrandIconRenderer` 单一真源统一驱动运行时矢量位图与构建期 `AppIcon.icns`。
- **空闲内存自洁与悬浮窗跨重启恢复**：主悬浮窗恒定锁定 `880 × 544` 零跳动尺寸，收起 `30s` 后自动释放视图树；全盘索引冷启动仅执行 `O(1)` 4 KB 快照头探测，空闲 `90s` 或收到系统内存压力信号时自动卸载内存节点与缩略图缓存；全部二级窗口关闭时置空 `contentView` 并回收堆页；桌面悬浮窗（插件自由画布 HUD、插件原生悬浮面板、屏幕贴图与系统脉搏）支持通过 `floating-window-session.json` 与持久 `PinnedSession/` 目录跨退出/关机重启自动恢复（区分用户主动关窗与系统关机退出）；退出重开冷启动独立遵循「开场动画」开关与「静默驻留状态栏」开关（后台驻留唤起时不重复播放）。

## 2. 统一快捷中枢 (`⌥Space`) 与可定制启动面板

- **模块化多场景启动页 (`home-layout.json`)**：支持最多 8 套场景 Profile 与 4 套官方预设切换、一键撤回编辑，自由编排 Bento 大磁贴（`2/3/4` 列）、混合高频坞（`8/16` 格，混排本机应用、插件、目录与协议书签）、最多 6 组命名胶囊架及可隐藏探索提示条，并打通搜索候选右键「钉上主页」与 `lucent-mcp` 零轮询热刷新。
- **并发全搜、`⌘K` 二级上下文动作流与「越用越懂你」自适应排序引擎**：
  - **统一 `⌘K` 上下文动作抽屉 (`OverlayActionCatalog` + `OverlayActionDrawerView`)**：对主浮窗中任意选中候选（文件、剪贴板图文/链接、计算结果、开发工具、短语、插件或应用）按 `⌘K` 即可在纯键盘流下呼出液态玻璃动作抽屉，一键串联原生动作（放进文件中转站、钉屏、离线 OCR、纯文本粘贴、钉到启动页）以及所有匹配 `accepts`/`acceptExtensions`/`acceptURLHosts` 的扩展插件与快捷脚本；
  - **应用启动与智能排序 (`AppUsageService`)**：融合前台活跃时长、启动频次 `log2` 加权、时间衰减与中文多音字拼音首字母检索；
  - **全候选点击频率与搜索词亲和排序 (`SearchAffinityStore`)**：覆盖应用、插件及子功能/索引词条、文件、快捷脚本、动态短语与静态系统命令，基于本地离线 Frecency（7 天半衰期）与精确/前缀搜索词亲和动态置顶高频点击项（隐私隔离剪贴板与计算结果，支持单项重置、一键清空与 `.lucentbackup` 自动备份）；
  - **全盘与外置盘秒搜 (`EverythingIndex` + `DirectoryEntryEnumerator` + `LCNTIDX3`)**：基于 Darwin `getattrlistbulk` 批量目录扫描（不支持卷自动无缝回退 POSIX `opendir`/`readdir`）、带尾部 `SHA-256` 与无环父指针校验的 `mmap` 二进制快照、`FSEvents` 实时增量同步及用户自定义排除路径；
  - **计算、10 维单位换算与离线开发工具箱 (`UnitAndCommandEngine` + `DevToolkitEngine` + `SnippetStore`)**：覆盖算式/百分比/科学函数、10 类中英自然单位换算、`;` 动态模板短语，以及离线时间戳、UUID、Base64/URL、JWT、JSON、哈希、色值与二维码生成；
  - **富媒体剪贴板历史 (`ClipboardMonitor` + `ClipboardHistoryStore`)**：支持文本、`#HEX`/`rgb` 色值、图片、GIF、视频与多文件固化快照，自动过滤密码管理器隐私标记与高危明文私钥，支持回车粘贴回原窗口、15 步删除撤回、容量/过期策略、应用黑名单、全量 `0600` 本地跨重启持久化（含临时媒体迁移至 `ClipboardHistory/`）以及按时间/媒体/分类/未收藏/全量一键批量清理。

## 3. 多显示器捕获、录屏与按需原生工具窗

- **逐屏原生 DPI 截图标注、长截图、离线识字与钉图 (`⌥A` / `⌥O`)**：基于 `MultiDisplayLayout`、`ScreenCaptureKit` 与 `AccessibilityElementMatcher` 实现跨屏混合 DPI 无损分片捕获、独立窗口无遮挡圆角抠取（支持去阴影）与带超时保护的无障碍子控件级下钻捕捉（滚轮切换层级、`F` 全屏选区、`⇧⌘A` 再次截图）；内置完整可选中矢量二次编辑引擎（100 步快照撤销栈、内部拖拽优先绘制防误触通道、`⌫` 单删、滚轮调粗细、双击文本/序号重编辑），覆盖 11 种实时标注工具（含三次贝塞尔曲线箭头、带引出箭头的递增序号、`CIGaussianBlur` 局部高斯模糊、正片叠底荧光笔、二次贝塞尔平滑画笔、圆角控制柄、实/虚/点划线型、5 色自定义色板与渐变色预设）；支持 `NSPasteboardItemDataProvider` 延迟渲染剪贴板、`PNG / JPEG / HEIC` 多格式变量模板导出与访达定位轻提示、工具栏按钮按需显隐、手动滚动长截图拼接 (`ScrollingCaptureStitcher` 行哈希去重叠、固定头尾剔除、侧边实时缩略图与分段撤回)，以及支持空格键原地无损二次标注的 `1:1` 悬浮穿透钉图 (`PinWindowController`) 与离线 `Vision` 中英 OCR / 条码识别 (`OCRResultWindowController`)。
- **零依赖流式区域 GIF 录屏 (`⌥G`)**：基于 `SCStream` + `ImageIO` 实现窗口吸附或跨屏选区 GIF89a 动图录制，支持静止帧差值压缩、灵动岛悬浮 HUD 控制与即录即粘。
- **物理鼠标平滑滚轮 (`MosMouseService`)**：独立区分外接物理鼠标与苹果触控板，仅对外接鼠标应用 `120Hz` 平滑插值、方向反转、`⇧` 横向滚动、`⌥` 加速与应用级排除；未开启或静止时零事件回调开销。
- **按需独立窗口与双栏文件工作台 (`⌥E` / `⌥M` / `⌥N`)**：提供零 `WKWebView` 原生 Markdown/代码阅读器、只读看图窗、支持 `'hev1'` 零拷贝硬解与同目录连播的 4K 影院播放器、双栏多选框选与只读 NTFS 护航的文件工作台、贴边自适应系统脉搏监控窗 (`⌥M`)、免 Root `nettop` 进程网络去向监控 (`⌥N`) 与分桶缓存清理。

## 4. 插件生态 (`Plugin v3.7`)、快捷脚本库与 AI 协议桥 (`lucent-mcp`)

- **纵深沙箱与高熵密钥保险箱 (`LCNTVLT2`)**：外部插件与快捷脚本统一经 `/usr/bin/sandbox-exec` 动态生成 Apple Seatbelt 策略隔离运行（净化宿主环境变量，无条件封锁系统钥匙串与宿主 `.vault`），通过 `ProcessSupervisor` 无死锁双管道与进程组精确取消监管；敏感凭据由 `LocalSecretVault` 采用 256-bit `AES-GCM` 双轨密封落盘；系统 TCC 权限遵循「宿主统一代申、单次 `0700` UDS 令牌桥接」并纳入全景权限审计矩阵。
- **原生卡片、置顶面板与自由画布挂件**：支持零前端自动生成原生设置表单、结构化交互卡片、`lucent://panel/<id>` 独立置顶轮询面板，以及授权 `window` / `floatingWindow` 后的沙盒化 `WKWebView` 透明桌面挂件（含网络规则拦截、坐标记忆与环境变更实时广播）。
- **单文件双向同步快捷脚本库 (`Quick Scripts`)**：支持 Zsh、Bash、Python 3、AppleScript、Swift 及任意 `#!` 自定义 Shebang 脚本，与 `@lucent.*` 头部注释双向同步，支持专属安全 SVG 图标、独立热键与 5 种输出反馈。
- **智能商店订阅、备份同步与内置 MCP 服务**：
  - 单输入框自动嗅探 GitHub 仓库、商店 `lucent-registry.json` 或 `.zip` 包，强制校验 `SHA-256` 与权限升级差异，附带 `plugin-demo/` 11 款原生 Swift 官方插件（含 `antigravity-pulse` 与 `gold-monitor` 自由画布悬浮窗）与 3 款内置精选模板；
  - **文件中转站与一键音频组合**：中转站采用原生液态玻璃浮窗（`RoundedGlassContainerView` + `DoubleSpecularBorder`），支持左右边缘磁吸贴边隐藏、悬停/拖入自动滑出、右键菜单与可选「拖出即移出」及跨重启会话恢复，条目由宿主长期保留并校验源文件身份；音频组合采用无边框双主题液态玻璃悬浮控制台（支持靠边胶囊收起与点击设备卡直切单个扬声器/麦克风），通过 Core Audio 回读核验并在部分失败时自动恢复，配合原生液态玻璃 HUD 反馈；
  - 支持应用与插件更新检查、含 `LZFSE` 压缩与可选口令密钥迁移的 `.lucentbackup` v2 归档及 HTTPS WebDAV 云端自动轮转同步；
  - 安装包内置零外部依赖 `lucent-mcp` 二进制，暴露 4 份规范资源与 21 项工具供 AI 客户端直接创建脚本、脚手架开发插件、编排启动面板，并在用户显式开启「设置 › 通用 › 允许 `lucent-mcp` 离线检索」后只读检索本地 `LCNTIDX3` 文件快照。

## 5. 当前已知运行约束

- 初次启用物理鼠标平滑、全局输入拦截或跨应用粘贴回填需在系统设置授予「辅助功能」权限；初次使用截图标注、离线识字或 GIF 录屏需授予「屏幕录制」权限（无商业公证证书环境下可通过 `scripts/resign-local-app.sh` 绑定本机签名免除升级重复授权）。
- 标准自动化验证由 `python3 -B scripts/check-docs.py`、`swift test --arch arm64`（`LucentTests` 单元与性能基线）及 `bash scripts/verify-macos.sh`（模块边界、行数门禁与 `lucent-mcp` 真实子进程往返）共同保障。
