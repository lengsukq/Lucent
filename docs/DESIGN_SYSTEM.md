# 液态玻璃设计规范

`Lucent` 采用纯正的 **macOS 原生双外观液态折射毛玻璃语言**：内置 **「晴霜浅色 (`Light Frost`)」** 与 **「曜石暗色 (`Obsidian Dark`)」** 两套对等高品质动态主题，并支持 **「跟随系统外观 (`followSystemAppearance`)」** 实时联动 `NSApp.appearance` 与 `NSApp.effectiveAppearance`。通过 AppKit 9-slice 真圆角穿透毛玻璃、统一连续曲率层次、双层镜面折射高光与克制的 Apple Blue 交互动效，让浮窗自然悬浮于桌面之上。

## 视觉层级与材质

1. **真圆角悬浮中枢外壳与双层镜面折射边（`RoundedGlassContainerView` + `DoubleSpecularBorder`）**：
   - AppKit 层 `RoundedGlassContainerView` 继承 `NSVisualEffectView`（浅色 `.popover` / 暗色 `.hudWindow` + `.behindWindow` + `.active`），生成 `28pt` 连续圆角 9-slice `maskImage` 并配合 `.cornerCurve = .continuous` 图层裁剪；浅色与暗色均完整启用双层镜面高光边（外层柔和发丝 + 暗色微冷银冰蓝折射，内层清亮顶部迎光白刃，并在唤起或切主题时掠过一道克制镜面流光，严格尊重 `reduceMotion`）；
   - 配合纯正 macOS 瓷白浅色 / 中性石墨暗色 `LiquidColors` 动态色板（`#0071E3` / `#0A84FF` Apple Blue 强调色、零霓虹径向杂光）与实时响应外观切换的 `CrispSearchTextField`（`allowsVibrancy = false`），任意壁纸下文字、占位符与按钮均保持高对比清晰可读；
   - 顶部提供极简抓手条（拖拽移窗，双击居中重置位置），搜索栏外边距、Bento 空白区、底栏空闲区及 `⌘`+左键全区域均可流畅拖动；面板锁定 **`880 × 544` 恒定零跳动尺寸**，4 态 `filterCapsuleBar` 采用 `@Namespace` + `matchedGeometryEffect` 实现液态水滴滑块过渡，切换时外框与主分割线完全静止。
   - 系统脉搏监控悬浮窗、文件中转站与音频组合控制台共享同源液态玻璃容器与双层描边；区域 GIF 录制采用顶部居中灵动岛式悬浮 HUD（`GifRecordingHUDView`）及跨屏 `sharingType = .none` 穿透虚线边界提示框；外部插件可复用 `PluginFloatingPanelWindowView` 弹出置顶实时监控面板，或在 `window` / `floatingWindow` 容器下渲染无边框透明自由悬浮挂件（`PluginCustomWebWindowController`，自动同步 `theme` 与 `appearance` 环境字段）。
2. **Bento 磁贴、物理弹性交互、3D 流光棱镜键帽品牌图标与开场动效**：
   - **专属点击特效与物理弹簧回弹（`LiquidInteractionEffects.swift` + `LiquidMotionModifiers.swift`）**：通过 `LiquidTapRippleModifier`（点击光学水波环 + 微缩过冲弹簧回弹）、`LiquidRimGlintModifier`（大圆角边缘银白镜面掠光）、`LiquidHoverSpecularModifier`（鼠标悬停顶光跟随）与统一 `LiquidMotion.pressSpring`（`response: 0.21, dampingFraction: 0.80`）为胶囊按钮、Bento 磁贴、结果行与主题卡片提供细腻触感反馈，并全面尊重「减弱动态效果」；
   - **3D 流光棱镜水晶键帽图标**（`BrandIconRenderer` / `LucentBrandIconView` / `scripts/generate-icon.swift` / `site/assets/icon.svg`）：统一应用于 `.icns` 应用图标、主悬浮框搜索栏与底栏、全部二级独立窗口顶栏微胶囊、设置中心侧边栏、关于页、迷你玻璃窗主题预览卡与静态站点；
   - **「一触流光，用完即焚」启动开场动画（`LaunchIntroController` + `LaunchIntroOverlayView`）**：采用银白、Apple Blue 与冰蓝光学棱镜折射动效，演绎 3D 键帽触压回弹、光学水波光环、流光扫光 Slogan 铭牌与轮廓扩散，无缝衔接 `WindowMotionAnimator` `.launcherFromIntro` 弹簧跃出 `880 × 544` 主悬浮框，过渡结束瞬间销毁开场面板并回收堆页；
   - 功能图标统一使用 `0.28` 超椭圆曲率的 `SquircleBadge` / `PluginIconBadge`；搜索候选行右侧内嵌 `⌘1`..`⌘9` 快选提示（`LiquidKeyHintBadge`），底部状态栏内聚呈现全键盘流提示。
3. **独立阅读窗与高密度内容层**：
   - Markdown 阅读窗口、插件 `view` 结构化卡片（`PluginStructuredViewCard`）与侧边预览文本使用 `solidReadable` 高对比可读玻璃表面，配合 `MarkdownBlocksView` 呈现代码框、引用左竖线、Callout 徽标与紧凑 GFM 表格。

## 圆角规范（Apple `.continuous` 亮暗统一同心连续曲率）

| 元素 | 圆角令牌 | 数值 |
| --- | --- | --- |
| 主悬浮快捷面板外壳（9-slice `maskImage` + 图层裁剪） | `LiquidRadii.panel` | `28pt` |
| 独立窗口主区域 / 文件中转站展开态 | `LiquidRadii.windowPanel` | `24pt` |
| Bento 磁贴 / 应用坞 / 英雄顶栏 | `LiquidRadii.bento` | `22pt` |
| 主搜索输入舱 | `LiquidRadii.searchBar` | `20pt` |
| 通用玻璃卡片 / 侧边预览区 / 主题卡片 | `LiquidRadii.card` | `18pt` |
| 键盘流高亮选中行 | `LiquidRadii.row` | `14pt` |
| 内部预览子卡片 / 代码块 / Callout / 过滤器胶囊 | `LiquidRadii.control` | `12pt` |
| 轻量图标盒 / 色块徽标 | `LiquidRadii.pill` | `10pt` |
| 按钮、灵动岛 HUD、状态徽章与快捷键提示 | `Capsule(style: .continuous)` | 全圆角 |

## 色彩与可访问性降级

- 全部颜色令牌通过 `NSColor(name:dynamicProvider:)` 动态响应 `NSApp.appearance`（晴霜浅色 `#F5F5F7` 瓷白 / 曜石暗色 `#141417` 中性石墨，Apple Blue 强调色 `#0071E3` / `#0A84FF`），禁止硬编码孤立色彩或霓虹弥散块。
- 通过 `SystemDisplayPreferences.shared` 监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 进行事件驱动 O(1) 缓存读取：
  - 当开启「减少透明度」（`reduceTransparency`）时，自动将窗口与卡片玻璃材质切换为高不透明度纯色表面；
  - 当开启「增强对比度」（`increaseContrast`）时，自动切换为高对比单色玻璃描边；
  - 当开启「减弱动态效果」（`reduceMotion`）时，自动关闭水波环、镜面掠光、悬停顶光与弹簧过冲动画。
