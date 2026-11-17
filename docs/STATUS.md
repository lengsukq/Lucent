# 当前实现状态

本文件如实记录当前仓库中已经编写并经过校验的真实实现，规划中能力见 [版本路线图](ROADMAP.md)。

## 已完成与已验证 (v0.9.2)

- **流光随行 (`LumaLink`) 多网卡识别切换、6 位配对码直显与手动连接修复 (`LumaLinkNetworkResolver`, `LumaLinkServer`, `PluginHostBridgeLumaLink`, `LumaLinkNetworkAndPairingCard`, `LumaLinkSettingsView`, `PluginDedicatedSettingsView`, `plugin-demo/lumalink-companion` v2.1.0)**：
  - **修复内网穿透/代理虚拟网卡抢占默认 IP 问题**：新增 `LumaLinkNetworkResolver` 自动识别并剔除 Clash/Surge 虚拟网段（`198.18.0.0/15`）、链路本地地址（`169.254.*`）与 `awdl`/`llw`/`anpi` 内部接口，将活跃网卡分级为「物理局域网 (`en0`/`en1`)」「内网穿透/异地组网 (`utun*`/`zt*`/`100.64.*`)」与「虚拟桥接」，默认始终优先选用真实局域网 IP，同时在 `LumaLinkConfig` 持久化 `preferredInterface` 与 `customConnectHost` 支持一键切换指定内网穿透网卡或自定义域名/端口；
  - **打通设置页与主浮窗双端配对码与手动连接面板**：在 `lumalink-companion` 插件独立设置页顶部直接挂载原生 `LumaLinkEmbeddedConsoleSection`（提供一键开启监听、网卡切换胶囊、端口与自定义地址配置、30pt 大号 6 位安全配对码、扫码二维码以及可逐项点击复制的主机 IP / 控制端口 / 配对码手动连接卡片）；Host Bridge 新增 `selectNetwork`、`setPort` 动作与监听就绪同步等待，官方示例商店 `lumalink-companion` 升级至 `v2.1.0` 新增「查看配对码与手动连接地址 (`--pin`)」和「切换连接网卡与 IP (`--networks`)」子功能。
- **插件注册期三级全局搜索接入控制与备份归档 v2 升级 (`PluginModels`, `PluginCommandModels`, `PluginCustomizationModels`, `PluginSearchIndex`, `BackupModels`, `BackupArchiveService`, `BackupArchiveCryptoAndCompression`, `BackupArchivePluginData`, `BackupCoordinator`, `BackupRestorePreviewCard`)**：
  - **注册期全局搜索分级声明与三态覆盖解耦**：`PluginManifest` 支持在注册时声明 `includeInGlobalSearch` 与 `searchIndexInGlobalSearch`，`PluginCommandSpec` 与 `search-index.json` 单条词条均支持独立声明 `includeInGlobalSearch`；`PluginUserOverrides` 升级为向后兼容旧版 `plugin-state.json` 的三态可选覆盖（`includeInGlobalSearchOverride`、`searchIndexGlobalOverride`、`commandSearchOverrides`），彻底解除主入口关闭对子命令搜索的一刀切锁死，并在插件独立设置页、内置插件及 `lumakey-mcp` 同步开放独立开关；
  - **备份归档 Schema v2（`PluginData` + 外部路径文件 + `LZFSE` 压缩 + 可选口令密钥迁移 + 恢复热刷新）**：升级 `.lumakeybackup` 至 `schemaVersion = 2`（完整兼容读取 v1 归档），新增 `LMKYBK02` 原生 `LZFSE` 压缩帧；自动归档 `PluginData/<id>/` 持久化数据与免前缀检索索引（自动过滤 `.tmp-*`、`cache/`、`*.log`、`*.sock` 并支持 `manifest.backupExclude` 规则），支持 `type: "path"` 字段通过 `includeInBackup: true` 携带主目录收件箱文件并以 `~/...` 跨机还原；支持可选备份口令（`SHA256x65536 + HKDF-SHA256 + AES-GCM`）端到端加密迁移插件 `secret` 密钥；补齐恢复前本地自动防呆快照（`Backups/pre-restore-latest.lumakeybackup`）以及恢复后 `SnippetStore`、`AppUsageService`（含挂起延迟写盘取消）与 `LocalSecretVault` 内存单例热刷新。

## 已完成与已验证 (v0.9.1)

- **示例与模板插件去重清理与精品化重写 + LumaLink 全功能商店化 (`plugin-demo/`, `PluginHostBridgeLumaLink`, `PluginStarterNetDiagTemplate`, `PluginStarterPortManagerTemplate`, `PluginStarterInboxNoteTemplate`)**：
  - **删除重复玩具模板并深度重写非重复扩展**：移除与 `DevToolkitEngine` 100% 重复的 `quick-hash-uuid` 及与远控/遥测重叠的 `host-snapshot`；将保留的 3 款正交扩展全面升级为 Python 3 + View v2 + 双语 `locales` 生产级插件——`sys-ip-dns`（多网卡 IPv4/IPv6、VPN `utun`、默认网关、系统代理与一键刷新 DNS）、`port-killer`（全量 `LISTEN` 端口表、内存/时长解析与带二次确认弹窗的 `SIGTERM`/`SIGKILL`）以及 `shell-note`（结构化 Markdown 速记收件箱、`#标签` 过滤、置顶/完成/确认删除、自动同步 `search-index.json` 与原生阅读窗深链）；
  - **全功能版 `plugin-demo/` 官方示例插件商店（`browser-hub` + `lumalink-companion` v2.0 + `notion-bookmarks`）**：新增 `plugin-demo/browser-hub` 三端浏览器书签与历史中枢（无锁 WAL 临时快照直连 Microsoft Edge / Google Chrome 多配置档与 Apple Safari 二进制 `Bookmarks.plist` / 阅读列表 / `History.db`，支持 `@edge`/`@chrome`/`@safari`/`@bm`/`@his`/`#目录` 过滤、自动同步 `⌥Space` 零延迟 `search-index.json`、一键唤起原浏览器与 Safari 完全磁盘访问权限友好引导）；同时将 `LumaLink` 剥离至 `plugin-demo/lumalink-companion` v2.0，三款插件统一由 `lumakey-mcp` 打包生成 `plugin-demo/lumakey-registry.json` 与 `dist/*.zip`；
  - **配对防爆破锁定与设备 Token 保险箱密封**：`LumaLinkServer` 改用 `SecRandomCopyBytes` 生成 CSPRNG 6 位配对码与 192-bit 设备令牌，连续 5 次输错自动锁定 60 秒并强制轮换新 PIN；`LumaLinkConfig` 将 `pairedDevices[].token` 迁入 `LocalSecretVault` 加密托管（磁盘 `lumalink-config.json` 与 `.lumakeybackup` 归档均不再留存明文 Token，旧配置读取时自动无感迁移擦除）。
- **子进程双管道无死锁重构、沙箱交互闭环与状态/网络边界加固 (`ProcessSupervisor`, `AppViewModel+Overlay`, `PluginDedicatedSettingsView`, `PluginInspectorCardsView`, `PluginCenterController`, `ClipboardPersistenceStore`, `WebDAVClient`, `PluginViewActions`)**：
  - **消除大载荷死锁、`SIGPIPE` 与浮窗隐藏全局误杀**：`ProcessSupervisor.run` 启用 `F_SETNOSIGPIPE`，先并发启动 `stdout`/`stderr` 有界截取与持续排空（Drain to EOF）再异步分块写入 `stdin`；移除 `handleOverlayHidden()` 中的全局 `terminateAll()`，仅随 `pluginRunTask?.cancel()` 精确回收前台浮窗子进程，保护后台商店安装、`nettop` 采样与视频重封装不被 `Esc` 误杀；
  - **插件沙箱设置 UI / MCP 闭环与防抖自动保存**：修复插件独立设置页 `if/else` 遮蔽问题（同时声明 `capabilities` 与 `resourceScopes` 时完整并列展示两张权限卡片），为 `PluginSandboxPermissionCard` 补齐 `network`/`filesystem`/`subprocess` 实时 Seatbelt 拦截开关并在 `lumakey-mcp` 同步暴露 `grantedResourceScopes`/`revokedResourceScopes`；`PluginCenterController` 在切换插件、运行测试或关闭窗口前自动 `flushPendingSaveIfNeeded()` 落盘未满 550ms 的防抖编辑；
  - **收藏剪贴板持久化、公网 WebDAV 强制 HTTPS 与深链临时文件隔离**：新增 `ClipboardPersistenceStore` 将已收藏剪贴板记录及临时媒体持久化至 `0600` `pinned-clipboard.json` 与 `0700` `ClipboardPinned/` 目录，重启自动恢复；`WebDAVClient` 拦截面向公网域名的明文 `http://` 连接及跨主机/降级重定向防止 Basic 凭证泄露（仅本机与 RFC1918/Tailscale/`.local` 局域网允许 `http://`）；`PluginDeepLinkParser` 对 `lumakey://reader?markdown=...` 实施严格文件名过滤、`SHA-256` 摘要防碰撞与 `0700`/`0600` 权限保护。

## 已完成与已验证 (v0.9.0)

- **安全模型加固：双轨高熵随机密钥保险箱 (`LMKYVLT2`) 与外部插件 OS 级沙箱隔离 (`LocalSecretMasterKeyStore`, `LocalSecretVault`, `PluginSandboxProfileBuilder`, `ProcessSupervisor`, `PluginPermissionAudit`)**：
  - **消除纯硬件标识低熵派生风险**：重构 `LocalSecretVault` 至 `LMKYVLT2`，新增 `LocalSecretMasterKeyStore`——在稳定签名 `.app` 构建下优先将 256-bit CSPRNG 随机主密钥存入系统 Keychain（零弹窗静默读取），在社区 Ad-hoc 构建或隔离测试环境下采用 `SecRandomCopyBytes` 生成 32 字节真随机种子（`0600` + `UF_HIDDEN` + 排除备份）叠加硬件绑定 `HKDF-SHA256` 信封派生；读取历史 `LMKYVLT1` 密文时自动无感升级为 `LMKYVLT2` 并移除旧文件，同时彻底消除非默认服务向 `/tmp` 散落密文的路径隐患；
  - **外部插件 `sandbox-exec` 系统级强制隔离与环境变量净化**：`ProcessSupervisor.run` 支持 `inheritHostEnvironment: false`，为外部脚本构造仅含安全基础变量与隔离 `TMPDIR` 的白名单环境（阻断宿主 Shell 令牌外泄）；新增 `PluginSandboxProfileBuilder` 将 `plugin.json` 的 `resourceScopes`（`network` / `filesystem` / `subprocess`）编译为 Apple Seatbelt 策略并支持用户级撤销（`setPluginResourceScopeGranted`），在内核层拦截未授权 IP 网络、越权磁盘写入与外部工具调用，并在策略末尾无条件封锁宿主 `.vault` 与 `~/Library/Keychains`。
- **索引快照完整性自愈 (`LMKYIDX3`)、核心模块五域无环拆分与标准测试/CI 体系 (`EverythingSnapshotStore`, `Package.swift`, `LumakeyTests`, `verify-macos.sh`, `.github/workflows/ci.yml`, `LICENSE`, `CONTRIBUTING.md`)**：
  - **`LMKYIDX3` 二进制快照防损坏加固**：在 `.lmkyidx` 快照尾部追加 32 字节 `SHA-256` 摘要，并在 `mmap` 加载期同时校验哈希摘要、节点计数边界与 BFS 父指针拓扑无环不变量（`parentID < currentIdx`），遇到断电截断或字节翻转时安全返回 `nil` 触发后台重扫；
  - **`LumakeyCore` 物理分层解耦与依赖门禁**：将原百余文件的单一核心模块拆分为 `LumakeyFoundation`、`LumakeySearch`、`LumakeyMedia`、`LumakeySystem` 与 `LumakeyCore` 五个单向无环 Swift 6 模块（`verify-macos.sh` 新增跨模块反向依赖静态审计）；
  - **双轨自动化测试、性能基准、PR CI 与开源合规文件**：新增基于 Swift 6 原生 `Testing` 框架的 `.testTarget(name: "LumakeyTests")`（兼容 CommandLineTools 与 Xcode，覆盖密钥迁移、Seatbelt 沙箱、快照防篡改、文件工作台异常护栏与 5,000 节点毫秒级检索/启动性能基线），配置 `.github/workflows/ci.yml` 自动门禁，并补齐根目录 [LICENSE](../LICENSE)（MIT）与 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 已完成与已验证 (v0.8.9)

- **剪贴板富媒体（图片 / GIF / 视频 / 多文件）快照固化、全格式写回与跨窗口无缝粘贴修复 (`ClipboardMonitor`, `ClipboardPasteboardIO`, `ClipboardPasteboardIO+Capture`, `FloatingPanelController`, `AppViewModel+Services`, `AppViewModel+WorkspaceOps`, `OverlayClipboardMediaLensCard`, `CheckClipboardMediaPaste`)**：
  - **容器与瞬态临时文件自动固化 + 视频专属分类预览**：针对从微信 (`RWTemp`/`MessageTemp`)、相册、Telegram 等沙盒容器或系统临时目录复制的图片与视频，捕获时即在 `lumakey-clipboard` 下按原文件名落盘快照，避免 `clearContents()` 后容器访问令牌失效或原临时文件被清理；新增剪贴板「视频」分类标签与异步首帧/分辨率/时长预览卡片 (`VideoClipboardLensCard`) 及多文件完整路径列表保留；
  - **全应用兼容双通道粘贴板写回**：图片写回时同时注入 `NSURL` (`public.file-url` 沙盒文件扩展)、`NSFilenamesPboardType` 以及真实重编码 `.png`（修复 JPEG/HEIC/WebP 误标 `.png` 头问题）、`public.jpeg`、`com.compuserve.gif` 与 `.tiff`，同时打通访达/桌面/终端、微信/Electron IM 以及浏览器/富文本编辑器粘贴；视频与多文件同步注入 `NSURL` 与 `NSFilenamesPboardType`；
  - **前序应用焦点自动归还、一键直粘 (`⇧↩`) 与文件工作台联动**：悬浮面板通过 `↩` / 点击条目 / `Esc` 收起时自动激活唤起前的前台应用窗口，确保紧接着按 `⌘V` 直接送达目标窗口，并支持 `⇧↩` /「直接粘贴」一键发送粘贴（同步剪贴板 `changeCount` 防止自捕获重复项）；文件工作台 (`⌥E`) `⌘V` 与右键菜单打通读取 `NSPasteboard.general` 中的文件、视频与原始位图。
- **双栏文件工作台排版舒展化、全应用页面单真源去重收敛与 AI Agent 一键接入 MCP 提示词 (`FileWorkspaceViews`, `FileWorkspaceToolbarViews`, `WorkspaceContentViews`, `AppNavigationState`, `MenuBarAndWindowCoordinator`, `WelcomeAndSettingsView`, `SettingsDetailSectionsView`, `AppCacheSettingsView`, `NetworkMonitorWindowView`, `PluginCenterView`, `PluginMCPSetupView`, `MCPAgentPromptBuilder`, `PluginDedicatedSettingsView`, `HotKeySettingsView`)**：
  - **文件工作台双栏模式重构**：双栏未选中文件时自动收起空态右侧预览栏（并在顶栏与预览栏提供一键切换开关），分栏头部拆分为「标签 + 完整路径胶囊」与「导航 + 自适应过滤框 + 视图/排序」双层布局，双栏列表精简冗余「类型」文字列并采用紧凑日期格式，彻底消除文件名被挤压成 `...`、分类筛选条硬截断与底栏文字碰撞；
  - **全应用页面去重（单页真源 + 直接跳转）**：全面收敛 5 处重复页面与窗口——合并独立「欢迎引导」窗口至「关于流光」页、移除设置内嵌双份「网络流量」页并统一路由至 `⌥N` 独立监控窗 (`NetworkMonitorWindowView`)、将单一检索范围选择器并入「通用与检索」（同步移除首页重复的插件开关与内存指标卡）、将零配置项的「剪贴板隐私」并入「存储与缓存」(`AppCacheSettingsView`)、移除插件中心与左侧边栏重复的「已装插件」列表页与右侧窄检查器栏（左侧「插件独立设置」统一挂载全部内置与外置插件，单页补齐导出/卸载闭环，市场/权限清单/全局热键页均一键直跳对应独立设置页）；
  - **MCP 页面整套 AI Agent 接入提示词生成 (`MCPAgentPromptBuilder` + `PluginMCPSetupView`)**：自动探测本机 `lumakey-mcp` 真实可执行路径与插件热重载目录，生成可直接复制发给 Claude Code / Cursor / Codex / Gemini CLI / Windsurf / Claude Desktop 等任意 AI Agent 的完整中英双语接入提示词（涵盖 CLI 一键注册命令、防覆盖合并的 `mcpServers` JSON、`lumakey_list_plugins` 连通性自检与 `lumakey://specs/plugin-v3` 开发规范指引，并支持可选附加一句话顺带开发任务与纯 JSON 复制）。
- **自定义插件商店入驻、单输入框智能地址识别与 `lumakey-mcp` 商店打包闭环 (`PluginStoreModels`, `PluginStoreSniffer`, `PluginStoreService`, `PluginStorePackager`, `PluginStoreSpecs`, `PluginStoreController`, `PluginStoreMarketplaceView`, `PluginStoreSheetsView`, `MCPStoreHandlers`, `CheckPluginStore`)**：
  - **单一地址栏自动识别（商店源 vs 单插件）**：在「精选市场」顶部提供统一的智能地址输入框（及一键粘贴与内置「入驻规范」速查弹窗），自动按「`.zip`/`.lumakeyplugin` 直链 -> GitHub 仓库主页探测 -> `.json` 顶层字段嗅探 -> 站点目录约定路径补全」分流为**自定义插件商店 (`lumakey-registry.json`)** 或**独立单插件**；
  - **多源入驻管理、SHA-256 防伪装校验与无损版本升级**：自定义商店订阅源持久化于 `plugin-registries.json`（自动纳入 `.lumakeybackup` 备份恢复），自动识别已装状态与语义化版本更新（`一键安装 / 更新 / 重装`）；安装时强制校验 `CryptoKit` `SHA-256`、通过私密 `0700` 沙盒 `ditto` 解压拦截软链接与路径逃逸，并比对包内真实 `plugin.json` 防止夹带商店词条未声明的权限；覆盖升级时无损保留用户自定义触发词、快捷键与密封密钥；
  - **规范内置 `lumakey-mcp` 与一键商店打包工具**：新增 `lumakey://specs/plugin-store-v1` 内置规范资源，配套 `lumakey_package_plugin_for_store`（自动 v3 校验、生成干净 `.zip`、计算 64 位 `sha256` 并创建/更新 `lumakey-registry.json`）、`lumakey_list_plugin_stores` 与 `lumakey_resolve_or_install_url`。

## 已完成与已验证 (v0.8.8)

- **外部扩展插件全链路原生化体验对齐 (`PluginNativePresentation`, `PluginIconBadgeView`, `PluginModels`, `PluginCommandModels`, `PluginViewActions`, `PluginConfigFormCard`, `PluginDedicatedSettingsView`, `PluginGalleryAndViewCard`, `OverlayPluginFilterAndContextViews`, `CheckPluginV5NativeExperience`)**：
  - **包内自定义图标、品牌色与自然分类标签**：支持在 `plugin.json` 声明包内相对路径图标（如 `icon.svg` / `assets/icon.png`，内置防目录逃逸校验与 `IconCache` 位图缓存）、`accentColor` 主题色令牌/`#HEX` 色值与 `categoryTag` 分类标签，列表词条同步支持 `PluginData` 图标与 `tintColor`，彻底告别千篇一律的紫底 `VIEW`/`SCRIPT` 脚本标签；
  - **外置插件双语本地化 (`locales`) 与宿主环境感知**：支持在 `plugin.json` 配置 `locales` 多语言覆盖（免重启实时联动插件名、分类标签、子功能标题与表单文案，且全语言词条均可被全局搜索命中），并在运行期向子进程注入 `stdin.locale` / `stdin.theme` 与 `LUMAKEY_LOCALE` / `LUMAKEY_THEME`；
  - **设置页即时自动保存、`Slider` 滑块与折叠式诊断面板**：外置插件配置表单对齐内置设置页体验，开关/分段/选择器/标签即时自动落盘、文本与密钥防抖/失焦自动同步，数值字段新增 `"control": "slider"` 原生滑块支持，并将缓存清理与实时调试器收敛进底部默认折叠的「开发者诊断」面板；
  - **富排版 Markdown 卡片与宿主独立窗口深链路由 (`PluginDeepLinkParser`)**：`PluginStructuredViewCard` 复用纯 Swift `MarkdownBlocksStackView` 渲染表格、代码块、引用与任务列表，并打通 `lumakey://reader`、`lumakey://image`、`lumakey://pin` 深链与 `PluginPostActionEffect` 窗口动作，外置插件可直接唤起独立阅读窗、看图窗与桌面悬浮钉图；
  - **子功能级独立全局热键 (`commandHotKeys`)、轻量状态摘要 (`status.json`) 与主浮窗胶囊对称化**：每项插件子功能支持独立录制全局快捷键（含 `silentWhenHotKeyTriggered` 静默瞬发与 `HotKeyConflictDetector` 三层冲突检测），支持通过 `effect.statusSummary` / `PluginData/<id>/status.json` 零子进程展示最新运行状态摘要，并在主浮窗顶部胶囊过滤条与 `Tab` 子模式中实现内置与外部插件完全对称的交互体验。

## 已完成与已验证 (v0.8.7)

- **应用内 `0600` AES-GCM 密钥保险箱与按需懒加载体系（零钥匙串弹窗）(`LocalSecretVault`, `PluginKeychainStore`, `WebDAVConfigStore`, `PluginSystem`, `AppViewModel+Plugins`, `PluginCenterController`, `BackupArchiveService`, `CheckSecretVault`)**：
  - **硬件绑定 `0700/0600` `AES-GCM` 密封存储**：新增 `LocalSecretVault`（通过 `IOPlatformUUID` + `UID` 经 `HKDF-SHA256` 派生 256-bit 对称密钥，采用 `LMKYVLT1` AAD 认证加密写入 `~/Library/Application Support/Lumakey/.vault/secrets.v1.enc`，强制 `0700` 目录与 `0600` 原子替换权限），彻底消除开发重编、跨版本升级及无证书开源分发时的传统 macOS 文件型钥匙串密码弹窗；
  - **静默免弹窗历史迁移、启动懒加载与双重备份隔离**：首次读取未命中时自动通过 `LAContext.interactionNotAllowed = true` 静默无弹窗迁移旧钥匙串记录；`AppViewModel.reloadPlugins()` 默认改为 `includeSecrets: false`，冷启动与列表刷新零密钥解密驻留，仅在实际运行插件或进入该插件独立设置页时按需加载；`BackupArchiveService` 同时从隐藏目录与文件名白名单双层排除 `vault` / `secret` 文件，确保密钥永不随备份外泄。

## 已完成与已验证 (v0.8.6)

- **中英双语多语言系统（首次启动跟随系统语言 + 免重启全局实时热切）(`LanguageModels`, `LocalizationService`, `LocalizationPatterns`, `LanguageManager`, `LanguageSettingsCardView`, `en.lproj/Localizable.strings`, `zh-Hans.lproj/Localizable.strings`, `CheckLanguageSystem`)**：
  - **首次启动自动识别系统语言并持久化偏好**：首次打开尚未生成 `~/Library/Application Support/Lumakey/language-config.json` 时，通过 `AppLanguageConfig.loadOrBootstrap()` 自动读取 `Locale.preferredLanguages` 首选系统语言（匹配 `zh*` 选用 `简体中文`，否则选用 `English`）并落盘记录；后续启动严格读取用户保存的语言配置，且 `language-config.json` 完整纳入 `.lumakeybackup` 本地/WebDAV 备份与恢复热重载；
  - **免重启全窗口实时切换**：在「设置中心 -> 通用与内存」与欢迎引导页提供双语卡片切换器 (`LanguageSettingsCardView`)，并在菜单栏、程序坞右键菜单及 `⌥Space` 全局搜索指令（`language` / `english` / `chinese` / `语言` / `英文` / `中文`）提供一键切换入口；通过 `LocalizedRootContainer`（动态注入 `.environment(\.locale, ...)` 驱动 905 条双语 `.lproj/Localizable.strings` 词表）配合 `L10n` 动态模板引擎，使全部 SwiftUI 浮窗/二级窗口、AppKit 菜单、窗口标题与内置插件元数据即时联动刷新。

## 已完成与已验证 (v0.8.5)

- **双内置视觉主题体系：「凝霜留白」与「霓彩流光」(`ThemeModels`, `ThemeManager`, `LiquidTheme`, `LiquidGlassComponents`, `ThemeSettingsCardView`, `FloatingPanelController`, `UnitAndCommandEngine`, `CheckThemeSystem`)**：
  - **两套鲜明独立的内置美学语言**：
    - **「凝霜留白」(`Pure Frost`)**：纯净云母磨砂底色、零背景弥散杂光、高不透明度白瓷/石墨卡片、细腻单层微描边、系统钴蓝强调色与干练几何圆角（面板 `24pt` / 卡片 `14pt`），清爽专注；
    - **「霓彩流光」(`Prism Pulse`)**：三重极光弥散光晕（电光青 + 珊瑚粉 + 星云紫）、通透液态玻璃、双层棱镜折射高光描边、三色光谱渐变胶囊与饱满圆角（面板 `28pt` / 卡片 `18pt`），灵动鲜明；
  - **全窗口实时热切、流式胶囊布局、候选锚定防跳回与标准公证分发流水线**：设置中心首页提供可视化微缩预览双主题切换卡 (`ThemeSettingsCardView`)，主浮窗与全部二级窗口实时联动刷新；新增 `FlowWrapLayout` 自适应流式折行布局消除多触发词单字竖排挤压，并全面去除第三方软件借名对比文案；新增 `LauncherSelectionAnchor` 消除后台索引合并与 `FSEvents` 刷新冲掉当前选中项的问题；全面清除源码与脚本中的个人盘符硬编码路径，补齐 `apps/macos/Lumakey.entitlements` 与 `scripts/release-macos.sh`（支持 `Developer ID Application` + `Hardened Runtime` + `xcrun notarytool` + `stapler` 正式公证分发，以及无证书环境下的干净开源通用 `.dmg` 打包）。

## 已完成与已验证 (v0.8.4)

- **插件内部子功能全局搜索注册与默认关闭的按需快捷按钮体系 (`PluginCommandModels`, `PluginBuiltinCommands`, `LauncherEngine`, `AppViewModel+PluginCommands`, `PluginCommandSettingsCard`, `OverlayBentoHomeView`, `OverlayFilterStripsView`)**：
  - **子功能声明与全局搜索直达 (`PluginCommandSpec` / `.pluginCommand`)**：外部插件（`plugin.json` `commands` 数组，如 `notion-bookmarks` 的「收藏剪贴板链接到 Notion / 同步刷新书签索引 / 浏览全部书签」及 5 款官方精选模板）与三大 `BUILTIN` 原生插件（`鼠标滚轮` 反转/平滑开关、`流光随行` 远控/RDP 开关、`系统脉搏` 悬浮窗/菜单栏开关）均可声明多项独立子功能，自动注册进 `⌥Space` 全局搜索与单插件专属列表，支持独立触发词、中文全拼/首字母匹配与命令后参数透传；
  - **快捷按钮严格默认全关、按需一键挂载 (`quickButtonCommandIDs = []`, `pinnedInOverlay = false`)**：所有新装与内置插件及全部子功能默认均无快捷按钮（主浮窗保持纯净零打扰）；用户可在单插件独立设置页、插件中心检查器、搜索候选右键菜单或 `⌘Return` 按需勾选想要挂载的子功能快捷按钮，开启后同步呈现在主浮窗首页「快捷按钮」栏与底部常驻栏实现一键瞬启。

## 已完成与已验证 (v0.8.3)

- **插件系统深度融合、独立插件设置列表与用户个性化覆盖体系 (`PluginCustomizationModels`, `PluginDataInspector`, `PluginStateOverrides`, `PluginDedicatedSettingsView`, `PluginDedicatedSettingsState`, `PluginDedicatedDataAndTestCards`, `OverlayPluginFilterAndContextViews`, `PluginConfigFormCard`, `LauncherEngine`, `CheckPluginV4Customization`)**：
  - **独立插件设置列表与专属全宽配置页**：重构设置中心侧边栏 (`WelcomeAndSettingsView`)，将「核心设置」与动态「插件独立设置」（统合 `BUILTIN` 原生插件与全部已安装外部插件）清晰分组；每个外部插件均拥有独立的全宽设置视图、实时全局热键录制胶囊、自定义触发词胶囊编辑器、`PluginData` 缓存与免前缀索引面板，并打通 `lumakey://settings/plugin/<id>` 深链、主浮窗 `⌘,` / `⌘Return` 直达路由及备份恢复后的 Keychain 密钥缺失引导；
  - **代码与个性化解耦 (`PluginUserOverrides`) + 增强型配置表单**：在不修改 `plugin.json` 的前提下持久化 `customKeywords`、`customHotKey`（联动 `HotKeySettingsView` 冲突诊断与一键改绑）、`pinnedInOverlay`、`includeInGlobalSearch`、`showInSettingsSidebar`、`priorityBoost` 与调用频次 `log2`/近度加权；`PluginConfigFormCard` 扩展支持 `number`（范围步进）、`path`/`directory`（`NSOpenPanel` 选择器）、`tags`（多标签胶囊）、`section` 分组及 Keychain 状态标识；
  - **主浮窗 (`⌥Space`) 子模式与跨模块动作注入**：新增插件模式顶部二级过滤条 (`OverlayPluginFilterStrip`)、选中插件按 `Tab` 进入单插件专属列表子模式（搜索框内嵌可按空退格 `⌫` / `Esc` 退出的作用域胶囊）、首页常用栏钉选插件条 (`OverlayBentoHomeView`)，以及基于 `accepts` 零子进程内存匹配的剪贴板侧边镜、Everything 文件预览、双栏文件工作台右键菜单与 Vision 离线识字窗四处跨模块「发送到扩展插件」直达动作（注入 `stdin.context`）与 `refreshIntervalSeconds` 按需静默索引刷新；`lumakey-mcp` 同步新增 `lumakey_update_plugin_overrides` 及上下文测试能力。

## 已完成与已验证 (v0.8.1)

- **插件系统 Plugin v3、全 App 权限审计矩阵、一过性 Host Bridge 与 `lumakey-mcp` v0.3.0 (`PluginModels`, `PluginPermissionAudit`, `PluginBuiltinRegistry`, `PluginHostBridge`, `PluginHostBridgeHandlers`, `PluginCenterView`, `PluginPermissionsMatrixView`, `MCPServer`, `MCPToolHandlers`)**：
  - 统一 `BUILTIN` 原生插件（`builtin-mos`、`builtin-lumalink`、`builtin-system-pulse`）与外部扩展插件模型：坚持非后台服务器/零常驻守护进程边界，关闭内置或外部开关即刻停用事件监听、定时器与助手进程，运行期直接复用宿主 TCC 权限；
  - 强制注册权限声明与全 App 权限全景清单：每个插件在 `plugin.json` 注册时必须显式声明 `capabilities`（无宿主权限需声明 `[]`），`PluginBuiltinRegistry` 为每个内置插件显式声明 `LumakeyPermission`；插件中心新增「权限清单」视图（`PluginPermissionsMatrixView`），直观展示整个 App 所需的 11 项系统 TCC/内核采样/宿主桥接权限、各自对应的调用插件与授权状态，以及纯沙盒插件列表；
  - 受控一过性 `Host Bridge`（`clipboard`、`ocr`、`everythingSearch`、`displayInfo`、`systemControl`、`lumaLinkStatus`）：外部插件声明能力默认关闭，由用户授权后仅在触发周期通过 `0600` 临时 UDS Socket + 48 位随机 Token 安全代理，严格校验 Token / 声明 / 授权三重边界并在退出后立即 `unlink` 销毁套接字；精选商店新增 `host-snapshot` Bridge 模板；
  - `lumakey-mcp` 升级至 `0.3.0`：在 `initialize` 返回架构指引 `instructions`，新增 `lumakey://specs/plugin-v3` 规范资源、`lumakey_app_permissions` 权限矩阵查询工具、`lumakey_list_plugins` 内置/外部全景列表以及必选 `capabilities` 参数校验。

## 已完成与已验证 (v0.7.1)

- **文件工作台全能力多选、液态蓝框选与安全文件操作引擎 (`WorkspaceFileOperations`, `WorkspaceMarqueeCanvas`, `AppViewModel+WorkspaceSelection`, `AppViewModel+WorkspaceOps`, `WorkspaceActionOverlays`, `WorkspaceContextMenuViews`)**：
  - 核心层 `WorkspaceFileOperations` 实现零破坏安全文件管理：新建文件夹 (`createFolder`)、单文件/目录重命名 (`renameItem`，拦截 `/`、`:`、空名与同名冲突并支持 APFS 大小写改名)、无损递增副本复制 (`copyItems`，同名自动生成 `name 副本.ext` / `name 副本 2.ext` 并拦截目录自包含递归)、跨目录移动 (`moveItems`，拦截父目录移入自身/子目录及同名覆盖)、以及严格调用 `FileManager.default.trashItem` 的系统废纸篓删除 (`trashItems`)，并基于 `VolumeInspector` 统一拦截只读 NTFS / 只读卷写入请求并给出可操作诊断；
  - 工作台支持单击锚点选择、`⌘+单击` 增减选择、`⇧+单击` 连续区间选择、`⌘A` 全选、`Esc` 清空、实时选中项数量与字节合计展示，以及在列表/网格/双列三态视图通用的液态蓝橡皮筋矩形框选 (`WorkspaceMarqueeContainer`) 与多选文件拖拽移动/按住 `⌥` 复制（支持拖入子文件夹或跨左右分栏互传）；
  - 配套底部浮动多选与待粘贴剪贴板操作条 (`WorkspaceFloatingActionBar`)、条目与空白区右键菜单、新建文件夹/重命名弹窗 (`WorkspacePromptSheetView`) 及仅在工作台 `isKeyWindow` 非输入焦点生效的快捷键桥接（`⌘C` / `⌘X` / `⌘V` / `⌘⌥V` / `⌘D` / `⌘⌫` / `⇧⌘N` / `Return`）；新增 `CheckWorkspaceOperations` 自动化单测覆盖全部安全边界。
- **全站实拍视觉巡检与 Liquid Glass 细节精修 (`OverlayResultRows`, `OverlayCommandView`, `CinemaPlayerWindowView`, `FileWorkspaceViews`, `FileWorkspaceToolbarViews`, `ScreenshotToolbarView`, `GifRecordingHUDView`, `WelcomeAndSettingsView`, `PluginCenterView`, `PluginGalleryAndViewCard`, `SnippetsSettingsView`, `BackupSettingsView`, `NetworkMonitorWindowView`)**：
  - 修复主悬浮中枢 (`OverlayResultRows` + `OverlayCommandView`) 因下标 `.id("row-\(index)")` 覆盖候选结构化身份导致的跨查询/跨 Tab 旧视图残留，切换为复合身份 ID 并修正键盘滚动定位；为文件作用域条与浮动操作条增加右侧渐隐遮罩；
  - 统一为 `GlassPillButtonStyle`、窗口置顶胶囊、截图标注工具条 (`668pt`)、GIF 录制/完成灵动岛 (`820pt`) 与影院播放器顶栏（`ViewThatFits` + 紧凑自定义倍速菜单胶囊 + 中段省略长文件名）补齐单行防折行与水平固有尺寸保护，彻底消除按钮折行、图标重叠与 `...` 挤压截断；
  - 重构文件工作台单/双栏自适应栅格（默认 `1320×760`、紧凑双栏头部导航与排序菜单、侧边窄预览自适应折行 Markdown 表格）与设置中心 12 项二级导航紧凑排布（`640pt` 默认高度一屏完整显示全 12 项）、插件参数布尔项去重及脚手架标签；`app.lumakey.macos` 升级至 `0.7.1` (build `17`)。

## 已完成与已验证 (v0.7.0)

- **Liquid Glass v2 视觉精雕与全键盘极客流 (`LiquidTheme`, `LiquidGlassComponents`, `OverlayCommandView`, `OverlayFilterStripsView`, `OverlayBentoHomeView`)**：
  - 引入严格同心圆角阶梯（外窗 `28pt` -> 搜索栏 `22pt` -> 卡片 `18pt` -> 候选行 `14pt`）与 `DoubleSpecularBorder` 双层高光镜面描边，升级 `LiquidBentoTileStyle` 按压微缩放阻尼回弹、`LiquidKeyHintBadge` 键帽与 `⌘1..9` 行级快选角标；
  - `AutoFocusSearchField` 接入灵动键盘操作流：`⌘1`..`⌘9` 秒执行对应行、`⌘C` / `⇧⌘C` 直接复制当前候选文本/路径/算式或色值、`⌘Return` 次级动作（访达定位或独立窗口打开）；Bento 首页升级原生动图录屏 (`⌥G`) 主磁贴及脉搏 (`⌥M`) / 插件 / 备份底栏快捷胶囊。
- **应用使用频率/时长智能排序与常驻钉选 (`AppUsageService`, `AppUsageTrackerController`, `LauncherEngine`)**：
  - 基于 `NSWorkspace` 前台激活时长累计（单次封顶防挂机失真）+ Lumakey 启动计数 + 系统频次的 `log2` 对数加权与 `32/(1+hoursAgo/24)` 近度时间衰减计算综合权重，冷启动零数据时通过 `AppSystemUsageProbe` 一次性融合 Spotlight `kMDItemUseCount`/`kMDItemLastUsedDate`、Dock 固定栏与运行中应用并原子落盘 `~/Library/Application Support/Lumakey/app-usage.json`；
  - 使用标准化路径 `pinnedAppIDs` 记录常驻钉选应用（钉住数量不限，Bento 常驻坞展示前 8 个）：空状态列表与带关键词全搜（`usageBoosts`）均优先置顶已钉应用与高频高时长应用，候选行与侧边详情镜提供图钉徽标、`usageSummary` 及「钉在常用栏 / 取消钉住 / 重置统计」菜单。
- **零依赖原生区域 GIF 动图录制 (`GifEncoderService`, `GifCaptureController`, `GifRecordingHUDView`)**：
  - 复用 `ScreenCaptureKit` (`SCScreenshotManager.captureImage` 区域帧循环采集) + `ImageIO` (`CGImageDestinationCreateWithURL` 流式 GIF89a 编码)，无需 `ffmpeg`：支持交互框选/窗口吸附、`10/15/20 FPS`、三档最大边长（640p / 960p / HD 1280px）、相邻近似静止帧差值合并压缩（默认上限 `45s`，支持 `1...300s`）与灵动岛悬浮录制控制条 (`⌥G` / 菜单栏 / 搜索命令 `gif`/`录屏`)；
  - 录制落盘至 `NSTemporaryDirectory()/lumakey-gifs/`（纳入 `AppCacheService` `.gifCaptures` 缓存桶管理），完成后自动以 `com.compuserve.gif` + `public.file-url` 双格式写入系统剪贴板，完成胶囊提供「复制 / 另存为 / 访达定位 / 预览 / 再来一段」。
- **全局热键可视化录制与三层冲突检测 (`HotKeyModels`, `HotKeyConflictDetector`, `GlobalHotKeyManager`, `HotKeySettingsView`)**：
  - 持久化 `~/Library/Application Support/Lumakey/hotkeys.json`，通过 `GlobalHotKeyManager.applyConfig(...)` 动态热重绑全部 10 项全局动作（新增区域 GIF 录制 `⌥G` 与一键本地备份，支持清空解绑与单键恢复默认）；
  - `HotKeySettingsView` 录制与插件热重载时实时执行三层冲突诊断：应用内动作/已启用插件热键互斥拦截、`~/Library/Preferences/com.apple.symbolichotkeys.plist` 系统快捷键与常见保留组合提示，以及 `Carbon` `RegisterEventHotKey` 真实第三方占用探测。
- **本地加密校验备份与原生 WebDAV 云同步 (`BackupArchiveService`, `WebDAVClient`, `BackupCoordinator`, `BackupSettingsView`)**：
  - 打包生成含顶层 `payloadSHA256`（`CryptoKit.SHA256`）校验的 `BackupEnvelope` JSON `.lumakeybackup` 归档，覆盖核心配置 JSON、自定义插件包与已收藏（单图 `<= 2 MB`）剪贴板条目；导入恢复前强制校验完整性、脱敏敏感字段并拦截路径穿越（拒绝 `..`、绝对路径与非法相对路径），恢复后即时应用生效；
  - 纯 `Foundation.URLSession` 实现 RFC 4918 WebDAV 客户端（`PROPFIND`/`MKCOL`/`PUT`/`GET`/`DELETE`，内置坚果云、Nextcloud、Synology NAS 与 Alist 预设），密码经 `Security` Keychain 安全存储，支持远端快照列表恢复与保留份数自动轮转（可配 `1...100`，默认保留最近 `10` 份）。
- **插件系统 v2、开发者瑞士军刀与快捷短语 (`PluginRuntimeAndWatcher`, `DevToolkitEngine`, `SnippetStore`, `PluginCenterView`, `SnippetsSettingsView`)**：
  - `plugin.json` 向后兼容扩展 `author`/`icon`/`hotkey`/`config`（`defaultValue`）表单字段，新增 `plugin-state.json` 启停与配置持久化、`PluginSystem.runPluginAsync` 异步子进程执行、丰富 `stdin` 上下文（`query`/`mode`/`config`/`clipboard`）、`PluginDirectoryWatcher` (`FSEvents` `350ms` 防抖热重载) 与 4 款一键安装的 `PluginStarterGallery` 官方脚手架（`sys-ip-dns`、`quick-hash-uuid`、`port-killer`、`shell-note`）；
  - 原生渲染 `mode: "view"` 返回的 `PluginViewPayload` 结构化交互卡片（`PluginStructuredViewCard`，支持 `metrics` 指标与 `items` 复制/打开 URL/带参重跑，`Esc` 优先收起卡片，非 JSON 平滑回退纯文本）；`lumakey-mcp` 同步升级 `lumakey://specs/plugin-v2` 资源与启停/安装/移除工具；
  - 内置零依赖 `DevToolkitEngine`（时间戳双向互转、UUID、随机密码、Base64、URL 编解码、MD5/SHA-256、JWT 离线解码、JSON 美化校验、`#HEX`/`rgb`/`hsl` 色板预览、`CoreImage` `CIQRCodeGenerator` 二维码生成并支持一键复制 PNG 或贴图置顶）与 `SnippetStore`（`snippets.json`，支持 `;` 前缀触发与 `{{date}}`/`{{time}}`/`{{datetime}}`/`{{uuid}}`/`{{clipboard}}` 动态占位符展开）。
- **Clean Code 架构拆分与检索精度优化 (`SystemDisplayPreferences`, `EverythingIndex`, `MarkdownDocumentParser`)**：
  - 新增 `SystemDisplayPreferences` 监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 提供 O(1) 无障碍透明度/对比度缓存，消除渲染帧 IPC 查询；`EverythingIndex.search` 升级为精确/词干/前缀/子串与文件名长度相关性排序（有界收集 `limit + max(limit * 4, 256)` 候选择优）；`MarkdownDocumentParser` 升级为 `Substring` 零分配行切片与单遍内联解析；拆分超长视图与控制器文件确保 `Sources/*.swift` 全量严格 `<= 300` 行；`app.lumakey.macos` 升级至 `0.7.0` (build `16`)。

## 已完成与已验证 (v0.6.5)

- **全栈性能优化（启动与空闲内存降幅、零分配检索、有界缩略图与底层采样减负）**：
  - **按需常驻与 `@2x` 紧凑图标 (`AppViewModel+IndexCache`, `EverythingSnapshotStore`, `IconCache`)**：启动阶段仅通过 `readHeaderMetadata(...)` O(1) 读取 `LMKYIDX2` 快照头节点数而不提前驻留全盘节点数组，仅在切入文件模式或输入检索词时 `mmap` 载入（隐藏 `90s` 自动卸载并保持节点计数显示）；移除启动预热 64 个全尺寸 `.icns` 图标（最高 1024px/4MB 级多图），改为按需将 Dock Top 8 图标离屏光栅化为紧凑 `@2x` 位图（`12 MB` `totalCostLimit` 上限）并异步检测 `HostToolingStatus`；
  - **24B 紧凑节点与零堆分配 UTF-8 匹配 (`EverythingIndex`, `EverythingQuery`)**：`IndexedNode` 移除死字段 `sizeBytes`/`modifiedAt` 与冗余小写副本后步长缩减为 `24 B`，查询引擎改用原地 ASCII 大小写折叠 UTF-8 字节扫描与按需后缀提取（消除 24 万次重复字符串分配）；
  - **热路径零多余计算与并发限流 (`LauncherEngine`, `FileModels`, `MediaClassifier`, `WorkspaceThumbnailPipeline`, `FileWorkspaceViews`)**：浮窗隐藏期间跳过候选排序与剪贴板空转重算、按键检索加入 `10ms` 防抖，预计算 `InstalledAppItem` 与 `PluginDescriptor` 小写字段，拆分 `LauncherTextAndMath.swift`，`FastFormatters` 以纯算术与线程安全 `localtime_r` 替代逐行 `ByteCountFormatter`/`DateFormatter` 分配，`PaneState` 缓存 7 类媒体统计，工作台缩略图经 `ThumbnailDecodeGate(4)` 与 `kCGImageSourceShouldCache: false` 限流防爆仓并于关窗/释放内存时同步清空 `WorkspaceThumbnailCache`；
  - **遥测/剪贴板轮询降噪与 Release 裁剪 (`SystemMonitorService`, `AppViewModel+Services`, `scripts/build-macos.sh`)**：缓存 `AppleSmartBattery` / `IOAccelerator` `io_service_t` 句柄并节流 `statfs("/")`，剪贴板空闲轮询放宽至 `1.5s`（配合呼出浮窗即时捕获），Release 启用 `-Xswiftc -O -Xlinker -dead_strip` + `strip -x`；`app.lumakey.macos` 升级至 `0.6.5` (build `15`)。

## 已完成与已验证 (v0.6.4)

- **截图后全路径自动写入系统剪贴板（即截即粘）**：
  - `ScreenshotCompositor` 新增通用剪贴板双格式写入（`copyImageToPasteboard(_:scale:to:)`、`copyImageFileToPasteboard(at:to:)` 同时写入带逻辑缩放尺寸的 `.png` 与 `.tiff`）与剪贴板快照恢复（`PasteboardSnapshot.capture`/`restore`）；
  - `ScreenCaptureCoordinator` + `ScreenshotCanvasView` + `ScreenshotToolbarView`：交互截图框选、窗口吸附及完成涂鸦/文字/序号标注后自动将合成图像写入 `NSPasteboard.general`，按「完成 (`Enter` / `⌘C` / 双击)」「钉图」「保存」「抠图」均保留或写入最新截图至剪贴板，`Esc`/右键取消时无痕还原原剪贴板内容（单按 `C` 复制 HEX 色值例外）；
  - `AppViewModel+Services` 在截图过程中暂停 600ms 剪贴板轮询防中间态污染历史，结束即同步 `capturePasteboardOnceIfChanged()`；`PinnedImageOverlayView` 抠图完成后自动复制透明主体 PNG，`OCRResultWindowController` 无文字时自动保留原图在剪贴板；`app.lumakey.macos` 升级至 `0.6.4` (build `14`)。

## 已完成与已验证 (v0.6.3)

- **工作台零阻塞异步加载、二进制 `mmap` 索引快照与 `FSEvents` 增量同步**：
  - `EverythingSnapshotStore` + `EverythingIndex+FSEvents` + `EverythingFSEventWatcher`：持久化紧凑二进制快照 `LMKYIDX1` 至 `~/Library/Caches/com.queensu.lumakey/everything-index/*.lmkyidx`，冷启动优先使用 `Data(..., options: .mappedIfSafe)` 秒开恢复索引，并通过 `FSEventStreamCreate`（仅监听本机与快速卷）以 `0.9s` 防抖增量重扫变更目录；
  - **工作台异步 SWR 与慢卷优化 (`AppViewModel+Workspace`, `WorkspaceDirectoryCache`, `DirectoryScanner`)**：`ensureWorkspaceLoaded()`/`refreshLocations()`/`refreshDirectory(pane:forceRescan:)` 全面异步化至后台 `Task.detached`，移除主线程阻塞扫描（如 `macfuse`/NTFS/SMB 跳过 `.tagNamesKey` 扩展属性读取），引入 `WorkspaceDirectoryCache`（48 项 LRU + POSIX `stat` mtime 校验，关窗保留最近 16 项），`WorkspaceContentViews` 与 `SideLivePreviewCard` 改用 `IconCache.shared.icon(for:)` 消除逐行主线程 `NSWorkspace.icon(forFile:)` 阻塞；
  - `AppCacheService` + `AppCacheSettingsView` 新增 `.diskIndexSnapshot` 缓存分桶可视化管理，设置内提供手动「重建磁盘缓存」，主浮窗索引空闲卸载延长至 `300s`；`app.lumakey.macos` 升级至 `0.6.3` (build `13`)。

## 已完成与已验证 (v0.6.2)

- **系统脉搏悬浮窗贴边自适应排布与零留白紧凑重构**：
  - `PulseDockEdge` + `UnconstrainedPulseHostingView`：解除 `NSHostingView.intrinsicContentSize` 对 `NSPanel` 缩窗尺寸的钳制，统一状态机 `reconcilePresentationState(animate:)`，彻底消除折叠为胶囊或贴边时残留空白大框的问题；
  - **贴顶横向 / 贴边竖行自适应排版**：贴靠屏幕顶部展示 `356 × 34` 精致横向指标条（CPU / 内存 / 功耗 / 网速），贴靠左右侧边展示 `58 × 182` 竖行纵列卡片；展开态缩紧至 `354 × 318` `.top` 对齐消除顶部大块空白并支持背景拖拽贴边；
  - `app.lumakey.macos` 升级至 `0.6.2` (build `12`)。

## 已完成与已验证 (v0.6.1)

- **工作台与独立窗口播放联动防双音轨**：
  - `PreviewPlaybackRegistry` + `InlineAVPlayerRepresentable`：追踪文件工作台侧边栏内嵌音视频播放器，并在触发「独立窗口播放」「视频置顶」「外部播放器打开」、双击打开媒体或其他独立窗口路由时自动调用 `pauseAll()` 暂停工作台预览（保留当前播放画面不清空）；影院转交 IINA 时同步暂停自身播放器。
  - `app.lumakey.macos` 升级至 `0.6.1` (build `11`)。

## 已完成与已验证 (v0.6.0)

- **内置网络流量与去向监控 (`⌥N`) + 应用缓存管理**：
  - `NetworkTrafficModels` + `NetworkTrafficSampler`：免 Root 调用 `/usr/bin/nettop -L 1 -J bytes_in,bytes_out,interface,state -x -n` 采集实时进程 `↓/↑` 速率与累计字节，支持 `proc_pidpath` 归属应用、Socket 远程 `IP:port`/接口/状态/服务标签及异步 `getnameinfo` 反向 DNS 去向追踪；窗口与面板关闭时采样立即停止（0% 后台 CPU）；
  - `AppCacheService` + `AppCacheSettingsView`：按桶盘点并按需清理 `lumakey-clipboard`、截图/钉图临时文件、`lumakey-cutouts`、`lumakey-cinema` 与内存索引（同时保护置顶文件与 `~/Library/Application Support/Lumakey`）；命令口令 `流量`/`network`、`缓存`/`cache` 直达。
- **毛玻璃同心大圆角视效与居中重构**：
  - `FrostedWindowVisualEffectView` + `LiquidTheme` + `FloatingPanelController`：主搜索栏、Bento 控制中心、系统脉搏胶囊与二级窗口全面升级半透明毛玻璃材质，Bento 卡片统一垂直居中 `76pt` / `22pt` 圆角 + `44pt` `0.32×` 超椭圆徽章，修复系统脉搏折叠胶囊回缩尺寸残影（`hosting.sizingOptions = []`）。
- **图片置顶、视频置顶、小窗与同目录视频播放列表**：
  - `WindowLevelStore` + `WindowChromeViews`：支持只读看图窗、OCR 窗、Markdown 阅读器、影院播放器与文件工作台的 `.floating` 窗口置顶切换与 `520×300` 小窗浮层；
  - `CinemaPlayerController` + `CinemaPlayerWindowView`：自动扫描同级目录视频生成播放列表（带搜索与 `连播` 自动续播），并将 `Hev1ResourceLoader` 改造为串行 `loaderQueue` 异步分块供给以消除 4K HEVC 起播卡顿。
- **独立工程与 Clean Code 门禁**：
  - `app.lumakey.macos` 升级至 `0.6.0` (build `10`)，`Sources/` 全部 `.swift` 文件均不超过 300 行且零 `@State`/`@FocusState` 宏依赖。

## 已完成与已验证 (v0.5.3)

- **独立工程与 Clean Code 门禁**：
  - 独立 Swift Package 仓库架构，`app.lumakey.macos` (`0.5.3`, build `9`)，零外部依赖；
  - `Sources/` 下全部 `.swift` 文件严格拆分，单文件均不超过 300 行。
- **暗黑沉浸式 4K 影院播放器与 `'hev1'` / MKV 硬件解码兼容 (`VideoPlaybackCompat` & `CinemaPlayerWindowView`)**：
  - 针对主流 4K HEVC `.mp4` 使用 `'hev1'` 标签导致 `AVPlayer` 黑屏/只出声的问题，新增零拷贝 `Hev1ResourceLoader`（`AVAssetResourceLoaderDelegate` 流式将 `moov` 中的 `'hev1'` 动态映射为 `'hvc1'`），无需写临时文件即可直接调用 Apple Silicon VideoToolbox 硬件解码（`SideLivePreviewCard` 右侧预览与独立影院窗口均受益）；
  - 针对伪装 `.mp4` 扩展名的 `Matroska / WebM / FLV / TS` 视频，自动调用 `ffmpeg` 无损极速重封装至临时 `.mp4` 并在关闭窗口时自动销毁；
  - 全新 `.darkAqua` 无边框影院界面：移除冗杂浅色顶栏与双层边框，采用黑曜石全画幅 + 红绿灯同排自动隐藏暗色磨砂 HUD（文件名、分辨率/硬解徽标、上下集、倍速菜单、右侧选集抽屉、一键用 IINA/外部播放器打开）。
- **混合智能 Dock 图标策略 (`MenuBarAndWindowCoordinator.syncDockPolicy`)**：
  - 在关闭全部标准窗口时保持零扰的纯菜单栏 `.accessory` 模式（或尊重“常驻 Dock”设置）；一旦打开 **文件工作台、影院播片、文档阅读、只读看图、OCR 识字或设置** 等任意窗口，立即自动切换为 `.regular` 在底部程序坞显示图标并支持 `⌘Tab` 与点击最小化恢复/Dock 右键窗口列表，关窗即收起。
- **稳定 macOS 证书签名与 TCC 免重授权体系 (`CodeSigningInspector` & `setup-local-signing.sh`)**：
  - `scripts/build-macos.sh` 自动优先选用钥匙串中的 `Developer ID Application`、`Apple Development` 或 `Lumakey Local Signer` 证书按内到外精确签名，不再依赖每次构建都变化的 Ad-hoc `cdhash`；`scripts/install-macos.sh` 改为 `rsync -a --delete` 原位同步更新；
  - 设置首页新增实时签名状态诊断卡与一键复制 `scripts/setup-local-signing.sh` 命令入口，运行一次生成 10 年受信任本地代码签名证书后，后续构建升级不再重复索要「辅助功能 / 屏幕录制」权限。
- **全页面与二级页面精致化布局升级 (`WindowChromeViews` & `SettingsDetailSectionsView`)**：
  - 为 `DragRegionNSView` 添加 `intrinsicContentSize = 1×1`，从根源消除 `WindowDragRegion` 纵向撑高标题栏与 Bento 首页的问题；
  - 新增 `SecondaryWindowScaffold`，统一所有独立二级窗口（OCR 识字、文件工作台、Markdown/代码阅读器、只读看图、影院播片、欢迎引导、流光设置）的 `28pt` 居中标题栏微胶囊与紧凑顶边距，去除多余左缩进空白与工作台双层顶栏；
  - 新增 `SettingsSectionHeroHeader`、`SettingsToggleCardRow`、自适应 `GlassInputField` 与双列/卡片式二级设置页面（含可点击试用的 Everything DSL 语法速查、剪贴板隐私规则卡、插件空态、热键网格与架构理念三支柱）。
- **开箱即用全盘 + 外置磁盘 POSIX Everything 秒搜**：
  - `EverythingScope.allVolumes` 设为默认检索范围并在应用启动及磁盘挂载/卸载时自动重建索引，直接覆盖本机主目录与全部外置 SSD / NTFS 大容量磁盘；
  - `EverythingIndex` 改用 POSIX `opendir`/`readdir`（`d_type` 免逐文件 `stat` RPC）、多卷轮询 BFS 队列与 `merging(_:)` 两阶段合并，毫秒级出图本机/SSD 文件后平滑并入慢速 FUSE/NTFS 外置盘，命中条目按需补齐大小与修改时间。
- **多排序、多筛选、多视图文件工作台与居中预览舞台 (`⌥E`)**：
  - `DirectoryScanner` 与 `FileModels` 新增创建时间/扩展名排序、`foldersFirst` 文件夹置顶、`WorkspaceMediaFilter`（全部/文件夹/图片/视频/音频/文档/压缩包）与 `WorkspaceDisplayMode`（列表详情 / 异步缩略图网格 / 紧凑双列）；
  - `SideLivePreviewCard`、`SidePreviewPanelView`、`OverlaySideLensView`、`ReadOnlyImageViewerSheet` 统一将横向/竖向图片与视频水平垂直居中呈现在右侧预览舞台；修正 `OCRResultWindowController` 顶栏纵向拉伸问题。
- **高对比度液态玻璃与零跳动 Tab 切换 (`880 × 544` 恒定面板)**：
  - `RoundedGlassContainerView` 切换至自适应浅/深色 `.popover` 材质，配合 `CrispSearchTextField`（关闭 vibrancy）与 `LiquidColors` 高对比主副文字/输入胶囊/边缘描边动态令牌，彻底解决浅色背景下文字与占位符泛白不清的问题；
  - 主浮窗锁定 `880 × 544` 恒定尺寸，并将 `everythingFilterStrip` / `clipboardCategoryStrip` 移入左侧列表区内部，主分割线与顶部胶囊在 `全部 / 文件 / 剪贴板 / 插件` 四态切换时零位移、零跳动；
  - `AppViewModel` 通过后台 `Task.detached` 执行 `LauncherEngine.rankCandidates` 并发排序，`EverythingIndex` 增加空查询与扩展名分类快速路径，`VolumeInspector` 改用 `NSWorkspace` 挂载/卸载事件缓存，`IconCache` 缓存应用图标与按扩展名/目录复用的系统文件图标，`startPreview` 增加 `65ms` 防抖。
- **系统脉搏监控悬浮窗与菜单栏实时遥测（默认关闭 · 设置可配）**：
  - `SystemMonitorConfig` 将 `floatingEnabled` 与 `showInMenuBar` 新装默认值设为 `false`（零后台采样占用），并在设置中新增专门的 `系统监控` 页签（`TelemetrySettingsView`），可自由开关桌面悬浮窗、切换顶部精简/常驻/贴边自动隐藏、开关菜单栏读数并自选 `CPU / 频率 / 内存 / 功耗 / 网速` 显示项；
  - `SystemMonitorSampler` 通过 Mach/IOKit/`getifaddrs` 实时采集 CPU 总占比与 P/E 簇负载、硬件 DVFS 等效频率 (`GHz`)、GPU 利用率、物理内存/压缩内存/Swap、实时整机功耗 (`W`)、网络 `↑/↓` 速率与磁盘可用空间；
  - `SystemPulseWindowController` 与 `SystemPulseOverlayView` 提供顶部精简胶囊（悬停或点击向下展开 4 卡片实时趋势面板）、拖至屏幕左/右/上边缘自动贴边隐藏与悬停滑出，以及菜单栏等宽紧凑读数开关。
- **智能选区截图标注、钉图与极速识字引擎 (`⌥A` / `⌥O`)**：
  - 基于 `ScreenCaptureKit`（`SCShareableContent` + `SCScreenshotManager.captureImage`）与 `CGPreflightScreenCaptureAccess` 实现全屏冻结、窗口智能吸附、8 控制点选区缩放、放大镜 `#HEX` 像素取色（`C` 键复制）、实时像素化马赛克预览、自动聚焦文字框、选中平移联动标注及鼠标右键快速清空/取消；
  - 通过隔离底层 `DragGesture` 避免拦截工具栏按钮点击；`⌥O` 识字模式框选或单击窗口松手即刻触发识别；
  - **修复 Vision 离线 OCR 卡死问题**：`VisionService` 显式将计算阶段绑定至 `MLComputeDevice.cpu`，消除 Apple Silicon Neural Engine ~36s 阻塞，实测亚秒级（~0.14s）完成中英混排 OCR 与条码扫描并弹出独立可编辑/合并换行的 `OCRResultWindowController` 窗口；
  - **重做悬浮钉图 (`PinInteractionLayer`)**：通过 AppKit `acceptsFirstMouse` + `window?.performDrag` 彻底修复钉图无法拖动问题，并新增鼠标滚轮缩放、`⌥+滚轮` 调透明度、悬停自动显隐操作条、右键功能菜单及 `Esc` 关闭。
- **LumakeyCore 核心引擎与 LumakeyMCP (`lumakey-mcp`)**：
  - `LauncherEngine`、`UnitAndCommandEngine`、`MosMouseService`、`MarkdownDocumentParser`、`MediaClassifier`、`ProcessSupervisor` + `MemoryStats`、`ClipboardMonitor`、`EverythingQuery`/`EverythingIndex`、`DirectoryScanner`、`BatchRenamePlanner`、`VolumeInspector`、`VisionService`、`PluginSystem` 及 stdio MCP 工具闭环。
- **Lumakey 原生界面与本机 `.dmg` 安装**：
  - `RoundedGlassContainerView` 9-slice `28pt` 连续圆角、Bento 控制中心、单一全搜框 + `Tab` 过滤、鼠标滚轮设置面板、独立销毁型 Markdown/文本/图片/视频阅读窗与全链路内存自洁；
  - `scripts/install-macos.sh` 支持一键构建 `dist/Lumakey.app`、打包 `dist/Lumakey.dmg` 并签名安装至 `/Applications/Lumakey.app`。

## 当前已知约束

- `LumakeyCheck` 覆盖全部 `LumakeyCore` 能力、Markdown 解析、统一全搜、`ProcessSupervisor` 超时强杀、鼠标滚轮配置、`MemoryStats`、`ScreenshotCompositor` 合成与像素采样、GIF89a 流式编码、应用使用度排序、三层热键冲突检测、`.lumakeybackup` SHA-256 归档与本地 WebDAV 协议往返、Plugin v2 + DevToolkit + Snippets、文件工作台安全操作与废纸篓隔离单测、以及真实 `lumakey-mcp` 子进程测试；GUI 交互、全局热键、真实 `ScreenCaptureKit` 屏幕录制弹窗与桌面滚轮拦截以实际运行验收为准；
- 初次使用物理鼠标平滑与滚轮反转需授权「辅助功能」，初次使用原生截图标注与区域 GIF 录制需授权「屏幕录制」（均可在系统设置中一键跳转授权）。
