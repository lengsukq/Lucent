# 系统架构与 Clean Code 约束

## 模块划分

`Package.swift` 将工程拆分为九个单向无环（DAG）Swift 6 目标（`.swiftLanguageMode(.v6)`），**零外部依赖**，并由 `scripts/verify-macos.sh` 自动校验跨模块导入边界：

1. **`LumakeyFoundation`**（`Sources/LumakeyFoundation` · 零上层业务依赖）：底层公共设施与安全底座，含双语系统（`LanguageModels`、`LocalizationService`、`LocalizationPatterns`）、双主题模型（`ThemeModels`）、统一诊断错误（`UserFacingError`）、代码签名检测（`CodeSigningInspector`）、双轨 256-bit 随机主密钥保险箱（`LocalSecretMasterKeyStore` + `LocalSecretVault` `LMKYVLT2`）以及子进程组生命周期监管与内存页回收（`ProcessSupervisor`、`ProcessCancellationHandle`、`MemoryStats`）。
2. **`LumakeySearch`**（`Sources/LumakeySearch` · 仅依赖 `LumakeyFoundation`）：全盘检索与安全文件操作域，含 `EverythingQuery`、`EverythingIndex`、`EverythingSnapshotStore`（带尾部 `SHA-256` 校验与父指针防环的 `LMKYIDX3` `mmap` 快照）、`EverythingIndex+FSEvents` + `EverythingFSEventWatcher`、`WorkspaceFileOperations`、`DirectoryScanner`、`WorkspaceDirectoryCache`、`BatchRenamePlanner`、`VolumeInspector`、`FileModels` 与 `MediaClassifier`。
3. **`LumakeyMedia`**（`Sources/LumakeyMedia` · 依赖 `LumakeyFoundation`、`LumakeySearch`）：媒体处理与文档解析域，含 `ScreenshotModels`、`ScreenshotCompositor`、`VisionService`（CPU 绑定离线 OCR/抠图）、`VideoPlaybackCompat`（零拷贝 `'hev1'` 硬解兼容）、`PreviewPlaybackRegistry` 与零 `WKWebView` 的 `MarkdownDocumentParser`。
4. **`LumakeySystem`**（`Sources/LumakeySystem` · 仅依赖 `LumakeyFoundation`）：系统遥测、外设与全局热键域，含 `SystemMonitorModels` + `SystemMonitorService`、`SystemDisplayPreferences`、`NetworkTrafficModels` + `NetworkTrafficSampler`、`MosMouseService`、`HotKeyModels` + `HotKeyConflictDetector` 与 `AppSystemUsageProbe`。
5. **`LumakeyCore`**（`Sources/LumakeyCore`）：上层业务编排与扩展引擎（通过 `LumakeyCoreExports` 聚合重导出上述四大基础域以保持上层兼容），聚焦统一搜索排序（`LauncherEngine`、`UnitAndCommandEngine`、`AppUsageService`、`DevToolkitEngine`、`SnippetStore`）、剪贴板与 GIF 粘贴桥接（`ClipboardMonitor`、`GifEncoderService`）、插件运行时与系统级沙箱（`PluginSystem`、`PluginSandboxProfileBuilder` `sandbox-exec` Seatbelt 强制隔离、`PluginHostBridge`、`PluginStoreService`）、远控伴侣（`LumaLinkServer`）与加密备份同步（`BackupArchiveService`、`WebDAVClient`）。
6. **`Lumakey`**（`Sources/Lumakey`）：macOS SwiftUI + AppKit 菜单栏应用与无边框悬浮窗口前端。
   - 窗口、双主题动态令牌与真圆角拖拽：`ThemeManager` + `ThemeSettingsCardView`（线程安全快照 + 全窗口实时切换 `凝霜留白` 与 `霓彩流光`）、`FloatingPanelController`（`RoundedGlassContainerView` 9-slice `28pt` `.popover` 材质 `maskImage`、恒定 `880 × 544` 零跳变容器、隐藏 30s 自动销毁）、`FrostedWindowVisualEffectView`、`WindowLevelStore`（全局 `.floating` 置顶与小窗管理）、`IconCache`（`@2x` 紧凑位图化 + `12 MB` `totalCostLimit`）、`LiquidTheme` + `LiquidGlassComponents`（同心圆角、`DoubleSpecularBorder`、`LiquidBentoTileStyle`）、`WindowChromeViews`、`AutoFocusSearchField`（支持 `⌘1..9` 快选、`⌘C` 候选复制、`⌘Return` 次级动作与空退格退出插件子模式）、`MenuBarAndWindowCoordinator`（混合智能 Dock 策略 + 动态热键应用 + 单插件独立设置路由）、`GlobalHotKeyManager`、`HotKeySettingsView`、`LumakeyApp`
   - 系统脉搏悬浮监控：`SystemPulseWindowController` + `SystemPulseOverlayView`（`⌥M`、`hosting.sizingOptions = []` 防尺寸残影、顶部精简胶囊悬停/点击展开、屏幕边缘吸附贴边隐藏、Sparkline 趋势图与菜单栏实时读数）
   - 内置网络流量与缓存管理：`NetworkMonitorController` + `NetworkMonitorWindowView`（`⌥N`、进程流量排序与去向 Socket 检查）、`AppCacheSettingsView`（分桶盘点、一键清理与置顶/配置保护）
   - 截图标注、原生 GIF 录制、钉图与独立 OCR 引擎：`ScreenCaptureEngine`（`ScreenCaptureKit` 冻屏 + 窗口清单 + `CaptureOverlayPanel` 右键取消/重选）、`ScreenshotSessionState`、`ScreenshotCanvasView`、`ScreenshotChromeViews`、`ScreenshotToolbarView`、`GifCaptureController` + `GifRecordingHUDView`（`⌥G` 交互框选 + `SCScreenshotManager` 区域帧循环采集 + 灵动岛悬浮控制条）、`PinWindowController` + `PinnedImageOverlayView`（`PinInteractionLayer` 首击拖拽、滚轮缩放、半透明调节与右键菜单）、`OCRResultWindowController`（独立可编辑/合并换行/置顶识字结果窗 + 一键发送到扩展插件）
   - 统一搜索面板、备份同步与独立插件设置：`AppViewModel*`（拆分为 `+Overlay`、`+Commands`、`+Services`、`+Plugins`、`+Workspace`、`+WorkspaceSelection`、`+WorkspaceOps`、`+IndexCache`）、`AppUsageTrackerController`、`OverlayCommandView` + `OverlayFilterStripsView` + `OverlayPluginFilterAndContextViews`、`OverlayBentoHomeView`、`OverlayResultRows`、`OverlaySideLensView` + `OverlayToolkitLensCards` + `PluginGalleryAndViewCard`、`BackupCoordinator` + `BackupSettingsView`、`SnippetsSettingsView`、`MosPluginSettingsView`、`TelemetrySettingsView`、`SettingsDetailSectionsView`、`WelcomeAndSettingsView`、`PluginCenterView` + `PluginDedicatedSettingsView` + `PluginDedicatedSettingsState` + `PluginDedicatedDataAndTestCards` + `PluginInspectorCardsView` + `PluginPermissionsMatrixView`
   - 独立窗口阅读与附加工作台：`DocumentReaderWindowView`、`MarkdownBlocksView`、`MediaSheets`（`ReadOnlyImageViewerSheet`、`BatchRenameSheet`、`WorkspaceHostView`）、`CinemaPlayerController` + `CinemaPlayerWindowView`（暗黑沉浸影院播放器 + 同目录视频播放列表/搜索/`连播` + 置顶/小窗 + IINA 一键直达）、`FileWorkspaceViews`、`FileWorkspaceToolbarViews`、`WorkspaceMarqueeCanvas`（液态蓝矩形框选与拖拽互传）、`WorkspaceActionOverlays` + `WorkspaceContextMenuViews`、`WorkspaceContentViews` + `WorkspaceThumbnailPipeline`（列表/异步限流缩略图网格/双列紧凑视图 + `ThumbnailDecodeGate(4)` + `32 MB` 有界缓存）、`SidePreviewPanelView`、`SideLivePreviewCard`（居中图文/兼容视频预览舞台）、`AppNavigationState`（`PaneState` 缓存媒体计数）
7. **`lumakey-mcp`**（`Sources/LumakeyMCP`）：嵌入 `.app/Contents/MacOS/lumakey-mcp` 的独立可执行 stdio JSON-RPC 2.0 服务器（`MCPServer` + `MCPToolHandlers` + `MCPPluginTestHandler`），在 `initialize` 暴露明确 AI `instructions`、`lumakey://specs/plugin-v1..v3` 规范资源及插件治理、商店打包与全 App 权限审计工具。
8. **`LumakeyTests`**（`Tests/LumakeyTests`）：基于 Swift 6 原生 `Testing` 框架的标准单元测试与性能回归基准套件（`swift test` 独立并行运行，兼容 CommandLineTools 与完整 Xcode），覆盖双轨密钥迁移、Seatbelt 沙箱规则、快照篡改/截断自愈、工作台异常拦截及检索/内存延迟基线。
9. **`LumakeyCheck`**（`Tests/LumakeyCheck`）：全链路系统集成自检程序，覆盖端到端功能回归与真实 `lumakey-mcp` stdio 子进程协议往返验证。

## 内存自洁与资源生命周期规范

- **浮窗与独立窗口即关即毁**：
  - 主悬浮窗在隐藏 `30s` 后释放 `panel` 与 `NSHostingView`；独立窗口在 `NSWindowDelegate.windowWillClose` 中立即置空 `contentView = nil` 并回收堆内存页。
  - 双栏文件工作台在启动时不预扫描目录，首次打开时全异步加载目录并缓存至有界 `WorkspaceDirectoryCache`（48 项 LRU + SWR），关闭后保留最近 `16` 个热点目录以便下次秒开，仅回收大预览状态与超出部分。
- **空闲索引卸载与系统内存压响应**：
  - Everything 启动优先对本地 `LMKYIDX3` 二进制快照执行 `readHeaderMetadata(...)` O(1) 探测（仅读取前 4 KB 展示节点数而不常驻内存），切入文件模式或输入搜索词时再通过 `Data(..., options: .mappedIfSafe)` 内存映射恢复并校验尾部 `SHA-256` 与父指针无环拓扑后启用 `EverythingFSEventWatcher`；主浮窗连续隐藏 `90s` 或收到系统 `.warning`/`.critical` 内存压力信号时卸载内存节点与缩略图缓存以便下次瞬时恢复。
- **子进程异步无死锁监管与精确取消**：
  - 所有外部脚本与工具通过 `ProcessSupervisor.shared.run(...)` 执行（启用 `F_SETNOSIGPIPE`、先启动 `stdout`/`stderr` 异步截断并排空管道直至 EOF，再异步分块写入 `stdin` 以彻底消除 `>64 KB` 双管道死锁与 `SIGPIPE` 误杀）；浮窗隐藏仅通过结构化 `Task.cancel()` 精确终止当前前台挂起插件，绝不误杀后台商店解包、网络采样或转码任务，应用退出时执行全局 `terminateAll()` 兜底回收。
- **物理鼠标零空闲功耗**：
  - `MosEngine` 仅在开启开关且获得辅助功能权限时安装 `CGEventTap`，静止帧平滑定时器在位移趋零后自动 `invalidate()`。
- **Swift 6 并发与 Clean Code 门禁**：
  - `Sources/` 下**任意 `.swift` 文件严格不超过 300 行**（`scripts/verify-macos.sh` 自动化检查）；零 `@State` 宏依赖以确保纯 CommandLineTools 工具链稳定构建。
