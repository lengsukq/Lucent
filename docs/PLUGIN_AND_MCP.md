# 插件系统与 MCP 接口规范

`Lucent` 定位为 **macOS 轻量生产力中枢**（而非多运行时应用中心、常驻 Web 网关或 `launchd` 守护进程调度器）。其 **Plugin v3.7（沙盒化自由画布 `WKWebView` HUD、窗口几何记忆与环境热同步、精细上下文过滤、阶段进度桥接与跨源批量更新版）** 与 **独立脚本快捷库 (`Quick Scripts`)** 延续「零常驻开销、按需触发、即关即回收」原则，将**内置原生插件 (`BUILTIN`)** 与**外部扩展插件 (`EXT`)** 统一纳入设置中心「插件独立设置」导航列表（支持按需折叠隐藏）、包内自定义图标与品牌色、中英双语自适应、子功能 (`commands`) 全局搜索与独立快捷键、默认关闭的按需快捷按钮与状态栏菜单挂载、自由画布/实时悬浮面板/阅读钉屏深链与全 App 权限审计矩阵，并通过同包交付的 `lucent-mcp` 服务向 AI 客户端暴露完整规范与接口。

## 一、统一注册模型、原生视觉、多语言清单与强制权限声明

每个插件（内置或外部）注册时**必须显式声明所需权限**，系统据其生成「**权限清单 (`PluginPermissionAudit`)**」，同时支持将插件内部多个细分功能声明为独立子功能 (`PluginCommandSpec`)，并通过 **用户个性化覆盖层 (`PluginUserOverrides`)** 实现代码不可变与高度用户自定义的解耦：

1. **内置原生插件 (`PluginBuiltinRegistry` · `BUILTIN`)**：
   - 与 `Lucent.app` 同进程运行，直接复用宿主已授 TCC 权限（无需单独签名或重复弹窗），关闭开关即停止监听、`CGEventTap`、定时器与助手子进程（零空闲消耗）。
   - 当前内置注册表及内置子功能（精简为两项高频桌面基础能力；「流光随行 · LumaLink 远控伴侣」已从主程序剥离至仓库 `plugin-demo/` 示例商店目录作为独立官方 Demo 插件 `lumalink-companion`，未安装时零常驻、零侧边栏占用）：
     - `builtin-mos`（鼠标平滑与滚轮反转）：声明 `[accessibility]`；内置子功能含 `切换鼠标平滑总开关`、`切换鼠标滚轮反转方向`、`切换 120Hz 平滑滚动插值`
     - `builtin-system-pulse`（系统脉搏桌面监控悬浮窗）：声明 `[telemetrySampling]`；内置子功能含 `开关系统脉搏桌面悬浮窗`、`开关菜单栏实时性能读数`
2. **外部扩展插件 (`plugin.json` 契约 · `EXT`)**：
   - 插件包目录 `~/Library/Application Support/Lucent/Plugins/<id>/plugin.json` 保持代码与静态资源不可变；可写缓存、免前缀检索索引 `search-index.json`（严格仅从隔离目录读取，忽略包内根目录旧路径）与零子进程轻量状态摘要 `status.json` 写入隔离目录 `PluginData/<id>/`（通过 `LUCENT_DATA_DIR` 与 `stdin.dataDir` 注入）；普通配置、授权与用户覆盖项持久化于 `plugin-state.json`，`.secret` 密钥字段由基于双轨 256-bit 随机主密钥的本机 `0600` `AES-GCM` 保险箱（`LCNTVLT2`）加密托管。
   - **`capabilities` 与 `resourceScopes` 双必选强校验 + OS 级 Seatbelt 强制隔离 (`PluginSandboxProfileBuilder`)**：注册时必须在 `plugin.json` 同时显式写出 `"capabilities"` 与 `"resourceScopes"`（`network` / `filesystem` / `subprocess`）数组；运行期由 `ProcessSupervisor` 切断宿主环境变量继承（仅注入纯净白名单与隔离 `TMPDIR`），并通过 `/usr/bin/sandbox-exec` 动态生成 Seatbelt 规则强制拦截未授权网络、用户目录写操作与越权子进程执行，同时无条件拉黑宿主 `.vault` 与 `~/Library/Keychains`。
   - **包内自定义图标、品牌色与自然分类标签 (`icon` / `accentColor` / `categoryTag`)**：
     - `icon` 既支持 SF Symbol（如 `"bookmark.fill"`），也支持插件包内的相对图像路径（如 `"icon.svg"`、`"assets/icon.png"`，严格拦截路径逃逸并经 `IconCache` 缓存渲染）；`PluginViewItem` 与 `search-index.json` 词条同样支持包内或 `PluginData` 下的自定义图标与 `tintColor` 色值；
     - 可选声明 `"accentColor"`（如 `"teal"`、`"#14B8A6"`）与 `"categoryTag"`（如 `"书签"`，未声明时展示为「扩展 / Extension」而非生硬的 `VIEW` / `SCRIPT`）。
   - **多语言本地化清单 (`locales`) 与宿主环境注入**：
     - 可选声明 `"locales": { "en": { "name": "...", "description": "...", "categoryTag": "...", "commands": { ... }, "config": { ... } } }`，免重启切换中英文时，外部插件的名称、分类标签、子功能标题与表单字段实时联动切换，且全局搜索同时匹配多语言词条；
     - 运行子进程时，`stdin` JSON 与环境变量同步注入当前语言（`stdin.locale` / `LUCENT_LOCALE`）与视觉主题（`stdin.theme` / `LUCENT_THEME`）。
   - **子功能全局注册 (`commands`)、三级独立全局搜索开关与子功能级全局热键 (`commandHotKeys`)**：
     - 插件可在 `"commands"` 声明多项子功能（含 `id`、`title`、`subtitle`、`keywords`、`icon`、`hotkey`、`arguments`、`passQuery`、`silentWhenHotKeyTriggered` 与可选 `includeInGlobalSearch`）；
     - **注册期分级全局搜索接入控制**：顶层 `plugin.json` 支持声明 `"includeInGlobalSearch": true|false`（主入口默认是否混入 `⌥Space` 全局搜索）与 `"searchIndexInGlobalSearch": true|false`（免前缀索引池默认是否混入全局搜索），每条 `commands[]` 与 `search-index.json` 的 `items[]` 均可独立声明 `"includeInGlobalSearch"`，并与用户设置页的三态覆盖（`includeInGlobalSearchOverride` / `searchIndexGlobalOverride` / `commandSearchOverrides`）按「用户显式覆盖 -> 条目/子命令声明 -> 主入口生效值」解耦决策（即使隐藏主入口也可单独放行指定高频子命令）；
     - **插件运行时数据与外部路径备份（Backup v2）**：`.lucentbackup` v2 自动采用原生 `LZFSE` 压缩纳入 `PluginData/<id>/` 持久化数据与检索索引（自动跳过 `.tmp-*`、`cache/`、`*.log`、`*.sock` 及 `plugin.json` 中 `"backupExclude"` 规则），支持 `type: "path"` 配置项声明 `"includeInBackup": true` 随包备份主目录文件并按 `~/...` 跨机还原，同时支持可选备份口令经 `SHA256x65536 + HKDF + AES-GCM` 端到端加密迁移插件 `secret` 密钥；
     - 除插件主入口热键外，每项子功能均可在独立设置页单独录制全局快捷键（持久化于 `overrides.commandHotKeys` 并纳入三层热键冲突检测），配置 `silentWhenHotKeyTriggered: true` 的动作类子功能按下热键即可后台静默瞬发。
   - **快捷按钮与状态栏菜单挂载 — 严格默认关闭、按需挂载**：
     - **默认状态下，所有插件与所有插件子功能均没有开启快捷按钮或状态栏菜单挂载**（`pinnedInOverlay = false`，`showInMenuBar = false`，`quickButtonCommandIDs = []`，`menuBarCommandIDs = []`），确保新装与新增插件零界面打扰；
     - 用户可在插件独立设置页为常用插件或具体子功能单独打开 **「快捷按钮」**、**「显示在状态栏菜单」** 或切换 **「显示在左侧设置栏」**（隐藏后归入侧边栏底部折叠组）。
   - **即时自动保存配置表单与折叠式开发者诊断**：
     - `PluginConfigFormCard` 支持 `text`、`secret`、`boolean`、`select`、`number`（支持 `"control": "slider"` 原生滑块或步进器）、`path`、`directory`、`tags`，交互改动即时自动落盘（文本输入防抖/失焦自动同步）；
     - 独立设置页默认置顶用户参数与子功能卡片，将缓存清理与实时运行测试器收纳于底部默认折叠的「开发者诊断」面板中。
   - **精细化上下文动作 (`accepts` / `acceptExtensions` / `acceptURLHosts`)、受控超时 (`timeoutSeconds`) 与阶段进度桥接**：
     - 声明 `"accepts": ["url", "text", "image", "file", "directory"]` 自动在剪贴板侧边镜、Everything 文件预览、工作台右键菜单与 Vision OCR 结果窗挂载联动动作，并可通过可选 `"acceptExtensions": ["pdf", "md"]` 或 `"acceptURLHosts": ["github.com"]` 精准收窄匹配目标；
     - 可选声明 `"minAppVersion"`（宿主最低版本门禁）与 `"timeoutSeconds"`（`3 ~ 30` 秒，默认 `8` 秒），执行期间可通过 `LUCENT_BRIDGE_SOCK` 发送零特权 `{"token":"...","op":"progress","message":"...","fraction":0.5}` 实时刷新状态提示；`PluginPostActionEffect` 返回 `"statusSummary"` / `"statusBadge"`（或写入 `PluginData/<id>/status.json`）后，设置页与侧边镜零子进程展示最新运行状态摘要。

### 完整示例如下

```json
{
  "schemaVersion": 3,
  "id": "notion-bookmarks",
  "name": "Notion 书签收藏",
  "version": "1.4.0",
  "description": "支持包内图标、中英双语、子功能独立快捷键、滑块配置与免前缀检索",
  "mode": "view",
  "keywords": ["bm", "bookmark"],
  "entry": "bin/notion-bookmarks",
  "author": "Lucent Official",
  "icon": "icon.svg",
  "accentColor": "teal",
  "categoryTag": "书签",
  "capabilities": ["clipboard"],
  "resourceScopes": ["network", "filesystem"],
  "accepts": ["url", "text"],
  "refreshIntervalSeconds": 180,
  "commands": [
    {
      "id": "add-clipboard",
      "title": "收藏剪贴板链接到 Notion",
      "subtitle": "读取当前剪贴板网页链接并一键写入 Notion 书签数据库",
      "keywords": ["bmadd", "收藏书签"],
      "icon": "plus.circle.fill",
      "arguments": ["--add-clipboard"],
      "passQuery": false,
      "silentWhenHotKeyTriggered": true
    }
  ],
  "config": [
    {
      "key": "cacheTtlSeconds",
      "label": "本地缓存有效期 (秒)",
      "type": "number",
      "control": "slider",
      "defaultValue": "120",
      "minValue": 0,
      "maxValue": 3600,
      "stepValue": 30
    }
  ],
  "locales": {
    "en": {
      "name": "Notion Bookmarks",
      "categoryTag": "Bookmarks"
    }
  }
}
```

## 二、主浮窗对称融合、富排视图卡片与宿主独立窗口深链

- **内置与外置对称的主浮窗子模式 (`Tab`)**：切入 `插件` 维度时顶部 `OverlayPluginFilterStrip` 统一展示全部活跃内置与外部插件胶囊；在任意搜索结果选中内置或外部插件按 `Tab`（或点击胶囊）即可进入**专属列表子模式**（置顶展示该插件全部子功能与索引词条，`⌘,` 直达对应设置页）。
- **自由画布窗口 (`window` / `floatingWindow`)、实时置顶悬浮面板、原生系统通知与宿主统一 TCC 代理 (`PluginCustomWebWindowController`, `PluginHostTCCBroker` & `PluginDeepLinkParser`)**：
  - **不限 UI 样式的自由窗口与透明无边框浮窗 (`lucent://window/<id>` / `effect.openWindow`)**：外部插件既可输出轻量 JSON 渲染默认结构化卡片，也可在 `plugin.json` 声明 `"window": { "entryHtml": "ui/widget.html", "chrome": "standard"|"frameless"|"hud", "transparent": true, "pinOnTop": true, "showInDock": false, "width": 392, "height": 488 }` 并申请 `"window"` 或 `"floatingWindow"` 权限（`showInDock` 默认标准窗为 `true`、无边框/HUD 浮窗为 `false`，由插件自行决定打开该窗口时是否让 Lucent 显示在程序坞），由宿主通过系统原生 `WKWebView` 渲染完全自定义的 HTML/CSS/Canvas/SVG 窗口或桌面悬浮挂件；容器自动注入 `window.lucent` 双向 SDK（支持 `lucent.run(args)` 调用插件后端、`lucent.bridge(cap, action, params)` 调用宿主桥、`lucent.permissions.request(cap)` 动态申请权限、`lucent.window.{getFrame,startDrag,resize,moveTo,animateFrame,morph,snapToEdge,setEdgeBehavior,setPinned,setShowInDock,setClickThrough,setOpacity,resetFrame,minimize,close}` 控制窗口与原生 `NSAnimationContext` 缓动动画，以及 `lucent.window.{onFrameChanged,onDragStart,onDragMove,onDragEnd,onEdgeProximity}` 实时事件订阅；任意标注 `data-lucent-drag` 的元素原生支持 120Hz 无边框拖拽与屏幕边界防丢失夹紧；浮窗可平滑收缩至最小 `64×36` 胶囊；强制透明度下限 `0.15`、单插件并发上限 `4` 窗、单窗后端并发上限 `6` 及菜单栏一键关闭全部自由窗口安全逃生入口，关窗即销毁视图与任务，零后台常驻）；
  - **宿主统一代申 macOS 系统 TCC 权限 (`PluginHostTCCBroker`)**：外部插件脚本不直接向系统索取高危 TCC 权限；当用户放行插件的 `selection`（含 `pasteBack` 原窗口回填粘贴）、`screenCapture`（交互框选截图 `captureInteractive`、主屏快照 `captureMainDisplay` 与像素取色 `sampleColor`）或 `notifications`（原生横幅通知）时，由签名宿主 `Lucent.app` 统一检测并代弹 macOS 系统授权请求或引导跳转隐私设置页；
  - **独立置顶实时悬浮面板 (`lucent://panel/<id>?pin=1&interval=30` / `effect.openFloatingPanel`)**：无需编写前端 HTML 的 `mode: "view"` 插件仍可通过主浮窗卡片右上角「悬浮窗」按钮、深链或 `openFloatingPanel` Effect 弹出复用 `SecondaryWindowScaffold` + `WindowLevelStore` 的独立置顶毛玻璃小窗，按设定秒数（`15s ~ 300s` 或手动）自动轮询刷新，关闭窗口即刻停止；
  - **宿主级系统原生通知横幅 (`effect.notification` / `notifications.send`) 与原窗口粘贴回填 (`effect.pasteText` / `selection.pasteBack`)**：支持投递 macOS 原生 `UNUserNotificationCenter` 横幅通知，并支持将插件处理后的文本自动写回唤起前的前台焦点窗口并触发 `⌘V`；
  - 同时支持通过 `item.openURL` 或 `effect`（`openReaderPath` / `openImagePath` / `pinImagePath`）触发 `lucent://reader?path=...`、`lucent://image?path=...&pin=1`、`lucent://pin?path=...`，唤起独立 Markdown 阅读窗、只读看图窗或屏幕悬浮钉图。
- **默认最小权限与一过性 UDS Socket（即用即毁）**：外部插件声明的 `capabilities` 默认全部关闭；授权后仅在单次执行周期于私密 `0700` 临时目录下创建 `0600` Unix Domain Socket 及 48 位随机 Token，退出/取消/超时后 `defer` 立即销毁。

### 可声明的宿主能力 (`PluginCapability`)

| Capability | 典型 Action & Params | 关联系统 TCC（宿主代申） / 说明 |
| --- | --- | --- |
| `window` | `open` (`{htmlPath,width,height,title}`)、`close` (`{windowID}`) | 容器权限：打开自定义 HTML/CSS/Canvas 独立自由窗口 |
| `floatingWindow` | `open` (`{htmlPath,chrome:"frameless"\|"hud",transparent:true,pinOnTop:true,clickThrough:false}`)、`close` | 浮窗容器权限：支持全局置顶、无边框透明背景、不抢焦点 HUD 与点击穿透（向下兼容 `window`） |
| `screenCapture` | `status`、`requestPermission`、`sampleColor` (`{x,y}`)、`captureMainDisplay`、`captureInteractive` | **屏幕录制 TCC**：由宿主代申并执行交互选区截图、主屏快照与屏幕像素 `#HEX` 取色 |
| `notifications` | `status`、`requestPermission`、`send` (`{title,subtitle,body,sound}`) | **系统通知 TCC**：由宿主代申并投递原生 macOS 横幅提醒 |
| `clipboard` | `read` (`{}`)、`write` (`{"text":"..."}`)、`writeImage` (`{"imagePath":"/abs/img.png"}`) | 读写系统剪贴板文本或写入 PNG/TIFF 双格式图片 |
| `selection` | `read` (`{}`)、`pasteBack` (`{"text":"..."}`) | **辅助功能 TCC**：读取前台应用选中文本，或自动切回原窗口执行 `⌘V` 粘贴回填 |
| `audio` | `play` (`{"path":"..."}`)、`speak` (`{"text":"..."}`)、`stop` | 复用宿主音频引擎播放音频文件或执行系统语音朗读 |
| `ocr` | `recognize` (`{"imagePath":"/abs/path.png"}`) | 复用 `VisionService` 离线识别中英文字与条码 |
| `everythingSearch` | `search` (`{"query":"...","limit":20}`) | 复用 `EverythingIndex` 内存树按 DSL 检索文件 |
| `displayInfo` | `list` (`{}`) | 返回活跃显示器 `displayID`、当前模式与可用分辨率 |
| `systemControl` | `status`、`setVolume`、`setMute`、`setCaffeine`、`setStatusScreen`、`clearStatusScreen` | 查询与安全调节系统音量/静音/防休眠状态，以及多屏全屏状态屏告示遮罩（支持键鼠防误触拦截与长按 `Esc` 安全退出） |
| `fileShelf` | `open`、`addContextItems`（均无参数） | 宿主原生液态玻璃文件托盘（支持左右贴边自动隐藏、悬停/拖入滑出、右键操作、可选拖出移出与跨重启恢复）。仅 `addContextItems` 的当前用户文件操作可加入选中项，持久引用按插件隔离保存 |
| `audioDevices` | `list` / `status`、`apply`（`{inputUID,outputUID,showFeedback?}`）、`setDevice`（`{direction,uid}`） | 读取和切换默认输入/输出（支持组合切换或单向直切），返回回读结果 `applied` / `unavailable` / `restored` / `partial`。仅桌面宿主可用，无麦克风采集 |
| `lumaLinkStatus` | `status`、`toggle`、`setEnabled`、`toggleRdp`、`regeneratePin`、`toggleCurtain`、`toggleCaffeine`、`setDisplayMode`、`restoreDisplays`、`revokeDevice` | 全闭环受控管理 LumaLink 监听、高清配对二维码生成、多屏 HiDPI 切换、物理防窥黑屏、防休眠及已配对设备解绑（绝不暴露设备 Token） |

## 三、独立脚本快捷库 (`Quick Scripts`)、权限审计矩阵与开发者套件

- **独立脚本快捷库 (`ScriptLibraryStore` & `ScriptRunner`)**：面向免 `plugin.json` 的单文件轻量快捷操作，支持设置中心可视化编写与 `~/Library/Application Support/Lucent/Scripts/` 目录单文件双向热同步（解析首部 `@lucent.*` 魔术注释）；原生支持 `Zsh`、`Bash`、`Python 3`、`AppleScript (osascript)`、`Swift` 及任意 `#!` 自定义 Shebang（如 `node`、`deno`、`ruby`），支持 `Scripts/icons/<id>.svg` 专属矢量图标与中英双语标题、5 种输出动作（轻提示、浮窗预览、复制结果、原窗口回填粘贴、阅读窗）、独立全局热键、启动页磁贴/高频坞及默认关闭的快捷按钮与状态栏菜单挂载，全程经 `PluginSandboxProfileBuilder` 强制执行 Seatbelt 隔离并纳入 `.lucentbackup` 归档同步。
- **权限全景清单 (`PluginPermissionAudit` & `PluginHostTCCBroker`)**：汇总系统 TCC（由宿主代申并在矩阵页提供实时状态与一键代申入口）、内核采样、容器/宿主桥接与 Seatbelt 资源作用域共 23 项细分权限，列出每项权限当前被哪些 `BUILTIN` / `EXT` 插件声明及授权状态，并在底部独立归集显式声明 `[]` 的纯沙盒插件。
- **内置工具与短语**：`LucentCore` 同时内置零子进程 `DevToolkitEngine` 与 `SnippetStore`。

## 四、原生 Stdio MCP 服务器 (`lucent-mcp` v0.3.3)

`lucent-mcp` 基于零依赖换行分隔 JSON-RPC 2.0（支持 `--plugins-dir <path>` 与 `--home-layout <path>`），暴露 `lucent://specs/plugin-v3`、`lucent://specs/plugin-store-v1`、`lucent://specs/home-layout-v1` 与 `lucent://specs/scripts-v1` 四项规范资源及 20 项工具：

| 工具名 | 必选 / 关键参数 | 作用 |
| --- | --- | --- |
| `lucent_list_plugins` | `includeBuiltin`（可选，默认 `true`） | 返回内置与外部插件的启用、包内图标/品牌色、多语言标题、已声明子功能 (`declaredCommands`)、子功能热键 (`commandHotKeys`)、已开启快捷按钮 (`quickButtonCommandIDs`)、运行态摘要 (`statusSummary`)、宿主能力与 Seatbelt 资源域 (`grantedResourceScopes`/`revokedResourceScopes`) 状态 |
| `lucent_app_permissions` | `onlyUsed`（可选） | 返回全 App 权限审计矩阵及纯沙盒 (`[]`) 插件列表 |
| `lucent_scaffold_plugin` | `id`, `name`, `keywords`, `capabilities`, `resourceScopes`（必选），`accepts`（可选） | 安全生成 `plugin.json` 与可执行 `run.sh` |
| `lucent_install_starter_plugin` | `id`, `overwrite` | 一键安装与内置工具零重叠的 3 款官方原生 Swift 实用插件模板（`sys-ip-dns` 网络栈与代理诊断、`port-killer` 开发端口与监听进程管家、`shell-note` 结构化 Markdown 速记收件箱；仓库 `plugin-demo/` 商店另提供 `antigravity-pulse`、`browser-hub`、`gold-monitor`、`lumalink-companion`、`notion-bookmarks`、`translate-hub`、`mac-pilot`、`quick-remind`、`screen-shield`、`file-shelf` 与 `audio-presets` 十一款预编译原生 `arm64` Swift 旗舰插件，零 Python 运行时依赖） |
| `lucent_validate_plugin` | `id` | 校验 `capabilities`、`resourceScopes`、包内图标安全边界、滑块数值范围、`commands`、`accepts` 与脚本权限 |
| `lucent_run_plugin_test` | `id`, `query`, `arguments`, `context`, `clipboardText`（可选） | 执行内置或外部插件测试（自动注入 `locale`/`theme`、模拟子功能 `arguments`、跨模块 `context` 与临时 Host Bridge） |
| `lucent_set_plugin_enabled` | `id`, `enabled` | 启停外部或 `BUILTIN` 插件 |
| `lucent_update_plugin_overrides` | `id`（必选），`customKeywords`, `customHotKey`, `commandHotKeys`, `pinnedInOverlay`, `quickButtonCommandIDs`, `commandSearchOverrides` 等 | 在不改动 `plugin.json` 的前提下配置用户级别名、主入口/子功能热键、按需快捷按钮与全局搜索可见性 |
| `lucent_remove_plugin` | `id` | 移除外部扩展插件目录、加密密钥与隔离数据目录（禁止删除 `builtin-*`） |
| `lucent_package_plugin_for_store` | `id`, `outputDir`（必选），`registryPath`, `storeId`, `storeName`, `downloadURL`（可选） | 校验外置插件并打包干净 `<id>.zip`（剔除隐藏文件与软链接）、计算 64 位 `sha256`，自动生成或更新 `lucent-registry.json` |
| `lucent_list_plugin_stores` | 无 | 列出当前已订阅的全部自定义插件商店源及收录插件 |
| `lucent_resolve_or_install_url` | `url`（必选），`install`, `installPluginId`（可选） | 自动识别任意地址是插件商店还是单个插件，支持一键订阅入驻或按需安装插件 |
| `lucent_get_home_layout` | `includeCandidates`, `includeNativeApps`（可选） | 读取当前启动页多场景 Profile、各分区明细，以及可用内置动作、已装插件、快捷脚本与已索引书签候选池 |
| `lucent_update_home_layout` | `selectProfileID`, `createProfile`, `applyPreset`, `sectionOrder`, `hiddenSections`, `bentoColumns`, `dockRows`, `upsertShelf`, `undoLastChange` 等 | 创建/切换场景 Profile、套用 4 套官方预设、调整四大分区显隐与网格密度、管理分组书签架或撤回上次改动，并通知运行中宿主实时热刷新 |
| `lucent_upsert_home_item` | `section`（必选），`kind`, `id`, `shelfID`, `scriptID`, `customTitle`, `customIcon`, `accentColor`, `index`, `moveOffset` 等 | 向 Bento 磁贴、混合高频坞或分组书签架新增、更新或移动启动项（内置动作、本机应用、快捷脚本 `script`、自制插件/命令、白名单书签 URL、本地目录、查询词） |
| `lucent_remove_home_item` | `id`, `section` 或 `resetPreset` | 移除指定主页启动项，或将当前 Profile 一键重置为指定官方预设 |
| `lucent_list_scripts` | `includeDisabled`, `includeCode`（可选） | 列出脚本快捷库中的全部单文件快捷脚本、中英名称、专属 SVG 图标状态、触发词、全局热键与沙箱作用域 |
| `lucent_upsert_script` | `title`（必选），`id`, `englishTitle`, `keywords`, `runtime`, `fileExtension`, `code`, `outputMode`, `iconSvg`, `icon`, `accentColor`, `hotKey`, `allowedScopes` 等 | 新建或更新单文件快捷脚本，支持 AI 自动中英命名与直接传入 `64×64` `<svg>` 矢量图标（`iconSvg`）落盘渲染，通知宿主实时热重载 |
| `lucent_run_script_test` | `id`（必选），`query`, `clipboardText`, `selectedText`（可选） | 在 Seatbelt 沙箱中实测运行指定快捷脚本并返回 `exitCode`、`stdout`、`stderr` 与耗时 |
| `lucent_remove_script` | `id`（必选） | 删除指定快捷脚本及其专属 SVG 图标并通知宿主刷新 |

## 五、自定义商店入驻与单插件地址自动识别规范 (`PluginStoreSniffer` & `lucent-registry.json`)

在插件管理中心的「精选市场」顶部提供单一统一的**智能入驻 / 直装地址栏**（以及内置的「入驻规范」速查弹窗），无需用户区分地址类型，输入任意 HTTPS 地址或本地路径即可自动嗅探识别：

1. **四级确定性自动嗅探优先级**：
   - **归档包直链（`.zip` / `.lucentplugin`）**：直接识别为**单个外部插件**，在私密 `0700` 临时沙盒解包校验 `plugin.json` v3 契约，弹出权限与来源确认卡后安装；
   - **GitHub 仓库主页（`github.com/{owner}/{repo}` 或 `/tree/{branch}`）**：优先探测默认分支下的 `lucent-registry.json`（命中则入驻为**自定义插件商店**）；若不存在则探测根目录 `plugin.json` 及 `releases/latest/download/{id}.zip` 或 `dist/{id}.zip`（命中则作为**独立单插件**预览安装）；
   - **JSON 清单直链**：顶层同时含 `"storeId"` 与 `"plugins"` 数组判为**插件商店**（持久化至 `plugin-registries.json`，自动纳入 `.lucentbackup` 备份）；含 `"id"` 与 `"entry"` 判为**单插件清单**；
   - **静态站点或本地目录根路径**：依次探测 `{base}/lucent-registry.json` 与 `{base}/plugin.json`。
2. **自定义商店清单契约 (`lucent-registry.json`)**：
   - 顶层包含 `"schemaVersion": 1`、`"storeId"`（`[a-z0-9-]+`）、`"storeName"`、可选 `"maintainer"` / `"updatedAt"` 以及 `"plugins"` 数组；
   - 每个商店词条必须显式声明 `"id"`、`"name"`、`"version"`、`"capabilities"`、`"resourceScopes"`、`"downloadURL"`（支持相对商店清单的 `./dist/<id>.zip` 路径）与 64 位十六进制 `"sha256"`；
   - **防伪装与无损升级**：从商店安装或更新时，强制比对下载包的真实 `SHA-256`，并校验包内 `plugin.json` 未夹带任何超出商店词条声明的 `capabilities` 或 `resourceScopes`；覆盖升级仅替换 `Plugins/<id>/` 代码包，完整保留用户的自定义触发词、快捷键与加密密钥。
