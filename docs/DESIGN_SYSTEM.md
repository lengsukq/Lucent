# 液态玻璃设计规范

`Lucent` 采用融合 **iOS Control Center 与 macOS Liquid Glass** 的精致视觉语言：通过 AppKit 9-slice 真圆角穿透毛玻璃、无直角渗漏外框、连续曲率层次与克制的高光边界，让浮窗自然悬浮于桌面之上。

## 视觉层级与材质

1. **真圆角悬浮中枢外壳与双层高光描边（`RoundedGlassContainerView` + `DoubleSpecularBorder`）**：
   - AppKit 层 `RoundedGlassContainerView` 继承 `NSVisualEffectView`（`.popover` + `.behindWindow` + `.active`），生成 `28pt` 连续圆角 9-slice `maskImage` 并配合 `.cornerCurve = .continuous` 图层裁剪；配合 `DoubleSpecularBorder`（外层顶亮底敛镜面高光 + 内层微缩暗衬）、`LiquidColors` 动态令牌与 `CrispSearchTextField`（`allowsVibrancy = false`），浅色/深色壁纸下文字、占位符与按钮均保持清晰可读；
   - 顶部提供 `18pt` 极简抓手条（拖拽移窗，双击居中重置位置），搜索栏外边距、Bento 空白区、底栏空闲区及 `⌘`+左键全区域均可流畅拖动；面板锁定 **`880 × 544` 恒定零跳动尺寸**，文件与剪贴板子过滤条内嵌于左侧列表区顶部，`全部 / 文件 / 剪贴板 / 插件` 四态切换时外框与主分割线完全静止。
   - 系统脉搏监控悬浮窗采用与主面板同源的 `20pt` `.popover` 液态玻璃胶囊，支持顶部精简横条悬停展开、三边吸附隐藏标签及高对比等宽 Sparkline 卡片；区域 GIF 录制采用顶部居中灵动岛式悬浮 HUD（`GifRecordingHUDView`）及跨屏 `sharingType = .none` 穿透虚线边界提示框；截图标注浮层改为每块显示器独立的 `.screenSaver` 无边框原生 DPI 分片层（`FirstMouseHostingView` 首击响应）+ `Canvas` 矢量渲染 + 底部两行 iOS 液态玻璃浮动工具条 + 像素放大镜取色框；外部插件可复用 `PluginFloatingPanelWindowView` 弹出置顶实时监控面板，或在 `window` / `floatingWindow` 容器下渲染无边框透明自由悬浮挂件（`PluginCustomWebWindowController`）。
2. **Bento 磁贴、键盘快选徽标、3D 流光棱镜键帽品牌图标与开场流光动效**：
   - 全新设计的 **3D 流光棱镜水晶键帽图标**（`BrandIconRenderer` / `LucentBrandIconView` / `scripts/generate-icon.swift` / `site/assets/icon.svg`）：采用深空黑曜蓝宝石底座、3D 阳极斜切透视水晶键帽侧壁、微凹球面高透键面、四象限切面星芒晶核与前后空间遮挡无缝环绕流光环，统一应用于 `.icns` 应用图标、主悬浮框搜索栏与底栏、全部二级独立窗口顶栏微胶囊、设置中心侧边栏、关于页、主题预览卡与静态站点；
   - **「一触流光，用完即焚」启动开场动画（`LaunchIntroController` + `LaunchIntroOverlayView`）**：非静默启动时在目标悬浮框同心舞台演绎 3D 键帽触压回弹、虹彩冲击波光环、流光扫光 Slogan 铭牌与轮廓扩散动画，无缝衔接 `WindowMotionAnimator` `.launcherFromIntro` 弹簧跃出 `880 × 544` 主悬浮框，并在过渡结束瞬间销毁开场面板与回收堆页（支持点击或任意按键瞬时跳过，以及在设置页随时重播）；
   - 控制中心 `3×2` Bento 磁贴与 8 格应用坞采用 `22pt` 连续圆角 `.ultraThinMaterial` + `LiquidBentoTileStyle`（按压 `0.975` 阻尼缩放回弹与双层描边）；
   - 功能图标统一使用 `SquircleBadge`（连续超椭圆圆角、线性渐变、顶部白色镜面高光与柔和投影）；
   - 搜索候选行右侧内嵌 `⌘1`..`⌘9` 快选提示（`LiquidKeyHintBadge`），底部状态栏内聚呈现 `↵ 打开`、`⌘1-9 快选`、`⌘C 复制`、`⌘↵ 访达/新窗`、`⇥ 切换分类` 与 `⎋ 收起` 全键盘提示。
3. **独立阅读窗与高密度内容层**：
   - Markdown 阅读窗口、插件 `view` 结构化卡片（`PluginStructuredViewCard`）与侧边预览文本使用 `solidReadable` 高对比可读玻璃表面，配合 `MarkdownBlocksView` 呈现代码框、引用左竖线、Callout 徽标与紧凑 GFM 表格。

## 圆角规范（Apple `.continuous` 同心连续曲率）

| 元素 | 圆角令牌 | 数值 |
| --- | --- | --- |
| 主悬浮快捷面板外壳（9-slice `maskImage` + 图层裁剪） | `LiquidRadii.panel` | `28pt` |
| 独立窗口主区域 / 钉图浮窗 | `LiquidRadii.windowPanel` / 钉图 | `24pt` / `20pt` |
| 主搜索输入舱 / iOS Bento 磁贴 / 应用坞 | `LiquidRadii.searchBar` / `LiquidRadii.bento` | `22pt` |
| 通用玻璃卡片 / 侧边预览区 | `LiquidRadii.card` | `18pt` |
| 键盘流高亮选中行 | `LiquidRadii.row` | `14pt` |
| 内部预览子卡片 / 代码块 / Callout | `LiquidRadii.control` | `12pt` |
| 四态胶囊、按钮、灵动岛 HUD、快捷键提示 | `Capsule(style: .continuous)` | 全圆角 |

## 色彩与可访问性降级

- 全部颜色令牌通过 `NSColor(name:dynamicProvider:)` 动态响应 macOS 浅色与深色模式，禁止硬编码孤立色彩。
- 通过 `SystemDisplayPreferences.shared` 监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 进行事件驱动 O(1) 缓存读取（避免每帧渲染重复跨进程 IPC 查询）：
  - 当开启“减少透明度”（`reduceTransparency`）时，自动将窗口与卡片玻璃材质切换为高不透明度纯色表面；
  - 当开启“增强对比度”（`increaseContrast`）时，自动增强玻璃描边线宽与边框不透明度。
