# 插件系统与 MCP 接口规范

`Lumakey` 定位为 **macOS 轻量生产力中枢**（而非多运行时应用中心、常驻 Web 网关或 `launchd` 守护进程调度器）。其 **Plugin v3.4（原生体验对齐、双语清单、子功能热键与深度窗口路由版）** 延续「零常驻开销、按需触发、即关即回收」原则，将**内置原生插件 (`BUILTIN`)** 与**外部扩展插件 (`EXT`)** 统一纳入设置中心「插件独立设置」导航列表、包内自定义图标与品牌色、中英双语自适应、子功能 (`commands`) 全局搜索与独立快捷键、默认关闭的按需快捷按钮 (`快捷按钮`)、主浮窗对称插件子模式、宿主独立阅读/钉屏深链与全 App 权限审计矩阵，并通过同包交付的 `lumakey-mcp` 服务向 AI 客户端暴露完整规范与接口。

## 一、统一注册模型、原生视觉、多语言清单与强制权限声明

每个插件（内置或外部）注册时**必须显式声明所需权限**，系统据其生成「**权限清单 (`PluginPermissionAudit`)**」，同时支持将插件内部多个细分功能声明为独立子功能 (`PluginCommandSpec`)，并通过 **用户个性化覆盖层 (`PluginUserOverrides`)** 实现代码不可变与高度用户自定义的解耦：

1. **内置原生插件 (`PluginBuiltinRegistry` · `BUILTIN`)**：
   - 与 `Lumakey.app` 同进程运行，直接复用宿主已授 TCC 权限（无需单独签名或重复弹窗），关闭开关即停止监听、`CGEventTap`、定时器与助手子进程（零空闲消耗）。
   - 当前内置注册表及内置子功能（均已自动注册到全局搜索，支持在主浮窗按 `Tab` 展开子功能列表，默认无快捷按钮）：
     - `builtin-mos`（鼠标平滑与滚轮反转）：声明 `[accessibility]`；内置子功能含 `切换鼠标平滑总开关`、`切换鼠标滚轮反转方向`、`切换 120Hz 平滑滚动插值`
     - `builtin-lumalink`（流光随行 · LumaLink 远控伴侣）：声明 `[accessibility, screenRecording, localNetwork, microphoneAndAudio, displayInfo]`；内置子功能含 `开关流光随行远控服务`、`切换流光随行 RDP 加速引擎`
     - `builtin-system-pulse`（系统脉搏桌面监控悬浮窗）：声明 `[telemetrySampling]`；内置子功能含 `开关系统脉搏桌面悬浮窗`、`开关菜单栏实时性能读数`
2. **外部扩展插件 (`plugin.json` 契约 · `EXT`)**：
   - 插件包目录 `~/Library/Application Support/Lumakey/Plugins/<id>/plugin.json` 保持代码与静态资源不可变；可写缓存、免前缀检索索引 `search-index.json` 与零子进程轻量状态摘要 `status.json` 写入隔离目录 `PluginData/<id>/`（通过 `LUMAKEY_DATA_DIR` 与 `stdin.dataDir` 注入）；普通配置、授权与用户覆盖项持久化于 `plugin-state.json`，`.secret` 密钥字段由本机 `0600` `AES-GCM` 保险箱加密托管。
   - **`capabilities` 与 `resourceScopes` 双必选强校验**：注册时必须在 `plugin.json` 同时显式写出 `"capabilities"` 与 `"resourceScopes"`（`network` / `filesystem` / `subprocess`）数组；无宿主桥接且无外部网络/写盘/子进程访问才可均声明为 `[]`（纯沙盒）。
   - **包内自定义图标、品牌色与自然分类标签 (`icon` / `accentColor` / `categoryTag`)**：
     - `icon` 既支持 SF Symbol（如 `"bookmark.fill"`），也支持插件包内的相对图像路径（如 `"icon.svg"`、`"assets/icon.png"`，严格拦截路径逃逸并经 `IconCache` 缓存渲染）；`PluginViewItem` 与 `search-index.json` 词条同样支持包内或 `PluginData` 下的自定义图标与 `tintColor` 色值；
     - 可选声明 `"accentColor"`（如 `"teal"`、`"#14B8A6"`）与 `"categoryTag"`（如 `"书签"`，未声明时展示为「扩展 / Extension」而非生硬的 `VIEW` / `SCRIPT`）。
   - **多语言本地化清单 (`locales`) 与宿主环境注入**：
     - 可选声明 `"locales": { "en": { "name": "...", "description": "...", "categoryTag": "...", "commands": { ... }, "config": { ... } } }`，免重启切换中英文时，外部插件的名称、分类标签、子功能标题与表单字段实时联动切换，且全局搜索同时匹配多语言词条；
     - 运行子进程时，`stdin` JSON 与环境变量同步注入当前语言（`stdin.locale` / `LUMAKEY_LOCALE`）与视觉主题（`stdin.theme` / `LUMAKEY_THEME`）。
   - **子功能全局注册 (`commands`) 与子功能级全局热键 (`commandHotKeys`)**：
     - 插件可在 `"commands"` 声明多项子功能（含 `id`、`title`、`subtitle`、`keywords`、`icon`、`hotkey`、`arguments`、`passQuery` 与可选 `silentWhenHotKeyTriggered`）；
     - 除插件主入口热键外，每项子功能均可在独立设置页单独录制全局快捷键（持久化于 `overrides.commandHotKeys` 并纳入三层热键冲突检测），配置 `silentWhenHotKeyTriggered: true` 的动作类子功能按下热键即可后台静默瞬发。
   - **快捷按钮 (`快捷按钮`) — 严格默认关闭、按需挂载**：
     - **默认状态下，所有插件与所有插件子功能均没有开启快捷按钮**（`pinnedInOverlay = false`，`quickButtonCommandIDs = []`），确保新装与新增插件零界面打扰；
     - 用户可在插件独立设置页、插件管理中心、搜索结果右键菜单或 `⌘Return` 为常用插件或具体子功能单独打开 **「快捷按钮」**。
   - **即时自动保存配置表单与折叠式开发者诊断**：
     - `PluginConfigFormCard` 支持 `text`、`secret`、`boolean`、`select`、`number`（支持 `"control": "slider"` 原生滑块或步进器）、`path`、`directory`、`tags`，交互改动即时自动落盘（文本输入防抖/失焦自动同步）；
     - 独立设置页默认置顶用户参数与子功能卡片，将缓存清理与实时运行测试器收纳于底部默认折叠的「开发者诊断」面板中。
   - **跨模块上下文动作 (`accepts`)、轻量运行态摘要 (`status.json`) 与按需同步 (`refreshIntervalSeconds`)**：
     - 声明 `"accepts": ["url", "text", "image", "file", "directory"]` 自动在剪贴板侧边镜、Everything 文件预览、工作台右键菜单与 Vision OCR 结果窗挂载联动动作；
     - `PluginPostActionEffect` 返回 `"statusSummary"` / `"statusBadge"`（或写入 `PluginData/<id>/status.json`）后，设置页与侧边镜零子进程展示最新同步/运行状态摘要。

### 完整示例如下（向后兼容 v1/v2/v3.x）

```json
{
  "schemaVersion": 3,
  "id": "notion-bookmarks",
  "name": "Notion 书签收藏",
  "version": "1.4.0",
  "description": "支持包内图标、中英双语、子功能独立快捷键、滑块配置与免前缀检索",
  "mode": "view",
  "keywords": ["bm", "bookmark"],
  "entry": "run.sh",
  "author": "Lumakey Official",
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
- **富排 Markdown 与宿主独立窗口路由 (`PluginDeepLinkParser`)**：
  - `PluginStructuredViewCard` 复用纯 Swift `MarkdownBlocksStackView` 原生渲染标题、代码块（带一键复制）、表格、引用、任务列表与高亮提示块；
  - 插件可通过 `item.openURL` 或 `effect`（`openReaderPath` / `openImagePath` / `pinImagePath`）触发 `lumakey://reader?path=...`（或 `?title=...&markdown=...`）、`lumakey://image?path=...&pin=1`、`lumakey://pin?path=...`，直接唤起宿主的独立 Markdown 阅读窗、只读看图窗或屏幕悬浮钉图。
- **默认最小权限与一过性 UDS Socket（即用即毁）**：外部插件声明的 `capabilities` 默认全部关闭；授权后仅在单次执行周期于私密 `0700` 临时目录下创建 `0600` Unix Domain Socket 及 48 位随机 Token，退出/取消/超时后 `defer` 立即销毁。

### 可声明的宿主能力 (`PluginCapability`)

| Capability | 典型 Action & Params | 返回 / 说明 |
| --- | --- | --- |
| `clipboard` | `read` (`{}`)、`write` (`{"text":"..."}`) | 读写系统剪贴板文本（脱敏保护） |
| `selection` | `read` (`{}`) | 复用宿主 Accessibility 读取当前前台应用选区文本 |
| `audio` | `play` (`{"path":"..."}`)、`speak` (`{"text":"..."}`)、`stop` | 复用宿主音频引擎播放在线缓存音频或系统语音朗读 |
| `ocr` | `recognize` (`{"imagePath":"/abs/path.png"}`) | 复用 `VisionService` 离线识别中英文字与条码 |
| `everythingSearch` | `search` (`{"query":"...","limit":20}`) | 复用 `EverythingIndex` 内存树按 DSL 检索文件 |
| `displayInfo` | `list` (`{}`) | 返回活跃显示器 `displayID`、当前模式与可用分辨率 |
| `systemControl` | `status`、`setVolume`、`setMute`、`setCaffeine` | 查询与安全调节系统音量/静音/防休眠状态 |
| `lumaLinkStatus` | `status` (`{}`) | 读取 LumaLink 监听状态（已脱敏，不含 PIN/Token） |

## 三、全 App 权限审计矩阵与开发者套件

- **权限全景清单 (`PluginPermissionAudit`)**：汇总全部 11 项系统 TCC、内核采样与宿主桥接权限，列出每项权限当前被哪些 `BUILTIN` / `EXT` 插件声明及授权状态，并在底部独立归集显式声明 `[]` 的纯沙盒插件。
- **内置工具与短语**：`LumakeyCore` 同时内置零子进程 `DevToolkitEngine` 与 `SnippetStore`。

## 四、原生 Stdio MCP 服务器 (`lumakey-mcp` v0.3.1)

`lumakey-mcp` 基于零依赖换行分隔 JSON-RPC 2.0（支持 `--plugins-dir <path>`），暴露 `lumakey://specs/plugin-v1..v3` 与 `lumakey://specs/plugin-store-v1` 资源及 12 项工具：

| 工具名 | 必选 / 关键参数 | 作用 |
| --- | --- | --- |
| `lumakey_list_plugins` | `includeBuiltin`（可选，默认 `true`） | 返回内置与外部插件的启用、包内图标/品牌色、多语言标题、已声明子功能 (`declaredCommands`)、子功能热键 (`commandHotKeys`)、已开启快捷按钮 (`quickButtonCommandIDs`)、运行态摘要 (`statusSummary`) 与授权状态 |
| `lumakey_app_permissions` | `onlyUsed`（可选） | 返回全 App 权限审计矩阵及纯沙盒 (`[]`) 插件列表 |
| `lumakey_scaffold_plugin` | `id`, `name`, `keywords`, `capabilities`, `resourceScopes`（必选），`accepts`（可选） | 安全生成 `plugin.json` 与可执行 `run.sh` |
| `lumakey_install_starter_plugin` | `id`, `overwrite` | 一键安装官方脚手架模板（`sys-ip-dns`、`quick-hash-uuid`、`port-killer`、`shell-note`、`host-snapshot`） |
| `lumakey_validate_plugin` | `id` | 校验 `capabilities`、`resourceScopes`、包内图标安全边界、滑块数值范围、`commands`、`accepts` 与脚本权限 |
| `lumakey_run_plugin_test` | `id`, `query`, `arguments`, `context`, `clipboardText`（可选） | 执行内置或外部插件测试（自动注入 `locale`/`theme`、模拟子功能 `arguments`、跨模块 `context` 与临时 Host Bridge） |
| `lumakey_set_plugin_enabled` | `id`, `enabled` | 启停外部或 `BUILTIN` 插件 |
| `lumakey_update_plugin_overrides` | `id`（必选），`customKeywords`, `customHotKey`, `commandHotKeys`, `pinnedInOverlay`, `quickButtonCommandIDs`, `disabledCommandIDs` 等 | 在不改动 `plugin.json` 的前提下配置用户级别名、主入口/子功能热键、按需快捷按钮与全局搜索可见性 |
| `lumakey_remove_plugin` | `id` | 移除外部扩展插件目录、加密密钥与隔离数据目录（禁止删除 `builtin-*`） |
| `lumakey_package_plugin_for_store` | `id`, `outputDir`（必选），`registryPath`, `storeId`, `storeName`, `downloadURL`（可选） | 校验外置插件并打包干净 `<id>.zip`（剔除隐藏文件与软链接）、计算 64 位 `sha256`，自动生成或更新 `lumakey-registry.json` |
| `lumakey_list_plugin_stores` | 无 | 列出当前已订阅的全部自定义插件商店源及收录插件 |
| `lumakey_resolve_or_install_url` | `url`（必选），`install`, `installPluginId`（可选） | 自动识别任意地址是插件商店还是单个插件，支持一键订阅入驻或按需安装插件 |

## 五、自定义商店入驻与单插件地址自动识别规范 (`PluginStoreSniffer` & `lumakey-registry.json`)

在插件管理中心的「精选市场」顶部提供单一统一的**智能入驻 / 直装地址栏**（以及内置的「入驻规范」速查弹窗），无需用户区分地址类型，输入任意 HTTPS 地址或本地路径即可自动嗅探识别：

1. **四级确定性自动嗅探优先级**：
   - **归档包直链（`.zip` / `.lumakeyplugin`）**：直接识别为**单个外部插件**，在私密 `0700` 临时沙盒解包校验 `plugin.json` v3 契约，弹出权限与来源确认卡后安装；
   - **GitHub 仓库主页（`github.com/{owner}/{repo}` 或 `/tree/{branch}`）**：优先探测默认分支下的 `lumakey-registry.json`（命中则入驻为**自定义插件商店**）；若不存在则探测根目录 `plugin.json` 及 `releases/latest/download/{id}.zip` 或 `dist/{id}.zip`（命中则作为**独立单插件**预览安装）；
   - **JSON 清单直链**：顶层同时含 `"storeId"` 与 `"plugins"` 数组判为**插件商店**（持久化至 `plugin-registries.json`，自动纳入 `.lumakeybackup` 备份）；含 `"id"` 与 `"entry"` 判为**单插件清单**；
   - **静态站点或本地目录根路径**：依次探测 `{base}/lumakey-registry.json` 与 `{base}/plugin.json`。
2. **自定义商店清单契约 (`lumakey-registry.json`)**：
   - 顶层包含 `"schemaVersion": 1`、`"storeId"`（`[a-z0-9-]+`）、`"storeName"`、可选 `"maintainer"` / `"updatedAt"` 以及 `"plugins"` 数组；
   - 每个商店词条必须显式声明 `"id"`、`"name"`、`"version"`、`"capabilities"`、`"resourceScopes"`、`"downloadURL"`（支持相对商店清单的 `./dist/<id>.zip` 路径）与 64 位十六进制 `"sha256"`；
   - **防伪装与无损升级**：从商店安装或更新时，强制比对下载包的真实 `SHA-256`，并校验包内 `plugin.json` 未夹带任何超出商店词条声明的 `capabilities` 或 `resourceScopes`；覆盖升级仅替换 `Plugins/<id>/` 代码包，完整保留用户的自定义触发词、快捷键与加密密钥。
