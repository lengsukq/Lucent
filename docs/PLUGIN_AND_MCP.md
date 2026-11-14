# 插件系统与 MCP 接口规范

`Lumakey` 定位为 **macOS 轻量生产力中枢**（而非多运行时应用中心、常驻 Web 网关或 `launchd` 守护进程调度器）。其 **Plugin v3** 架构延续「零常驻开销、按需触发、即关即回收」原则，将**内置原生插件 (`BUILTIN`)** 与**外部扩展插件 (`EXT`)** 统一纳入插件中心与全 App 权限审计矩阵，并通过同包交付的 `lumakey-mcp` 服务向 AI 客户端暴露完整规范、工具与权限清单。

## 一、统一注册模型与强制权限声明

每个插件（内置或外部）注册时**必须显式声明所需权限**，系统据其生成「**权限清单 (`PluginPermissionAudit`)**」，清晰展示整个 App 所需的全部权限及其对应的使用插件：

1. **内置原生插件 (`PluginBuiltinRegistry` · `BUILTIN`)**：
   - 与 `Lumakey.app` 同进程运行，直接复用宿主已授 TCC 权限（无需单独签名或重复弹窗），关闭开关即停止监听、`CGEventTap`、定时器与助手子进程（零空闲消耗）。
   - 当前内置注册表：
     - `builtin-mos`（Mos 鼠标平滑与滚轮方向）：声明 `[accessibility]`
     - `builtin-lumalink`（流光随行 · LumaLink 远控伴侣）：声明 `[accessibility, screenRecording, localNetwork, microphoneAndAudio, displayInfo]`
     - `builtin-system-pulse`（系统脉搏桌面监控悬浮窗）：声明 `[telemetrySampling]`（IOKit/Mach 只读采样）
2. **外部扩展插件 (`plugin.json` v3 契约 · `EXT`)**：
   - 存放于 `~/Library/Application Support/Lumakey/Plugins/<id>/plugin.json`，启停状态、表单配置与能力授权持久化于同级 `plugin-state.json`（`FSEvents` `350ms` 防抖热重载）。
   - **`capabilities` 必选声明**：注册时必须在 `plugin.json` 中显式写出 `"capabilities"` 数组；若为纯沙盒脚本（不访问任何宿主特权能力），必须写为 `"capabilities": []`。缺失 `"capabilities"` 或包含未知能力名将在加载与 `lumakey_validate_plugin` 时报错。

### 完整示例如下（v1/v2 `author`、`icon`、`hotkey`、`config` 保持兼容）

```json
{
  "id": "host-snapshot",
  "name": "宿主显示与音频速览",
  "version": "1.0.0",
  "description": "通过 Host Bridge 零弹窗读取活跃显示器、音量与防休眠状态",
  "mode": "view",
  "keywords": ["disp", "snapshot", "bridge"],
  "entry": "run.sh",
  "author": "Lumakey Official",
  "icon": "display.and.arrow.down",
  "capabilities": ["displayInfo", "systemControl"],
  "config": []
}
```

## 二、可控复用宿主能力（Host Bridge 协议）

- **默认最小权限**：外部插件声明的 `capabilities` 在 `plugin-state.json` (`grantedCapabilities`) 中默认全部为**关闭**，需由用户在设置 → 插件中心「配置预览 → 宿主能力授权」或对照「权限清单」显式授权开启。
- **一过性 UDS Socket（即用即毁）**：当 `capabilities` 非空且被按需触发时，宿主仅在本次执行周期创建一个权限 `0600` 的临时 Unix Domain Socket（`/tmp/lk-<rand>.sock`）及一次性随机 Token（`48` 位十六进制），通过环境变量 `LUMAKEY_BRIDGE_SOCK` / `LUMAKEY_BRIDGE_TOKEN` 与 `stdin` JSON 的 `bridge` 字段注入脚本；脚本退出或超时后 `defer` 立即取消监听并 `unlink` 销毁套接字文件。
- **三重校验**：每次连接服务端严格校验 `token`、是否在 `plugin.json` 声明 (`declaredCapabilities`) 以及是否获用户授权 (`grantedCapabilities`)，越权请求返回 `{"ok":false,"error":"invalid_token|capability_not_declared|capability_not_granted",...}`。

### 可声明的宿主能力 (`PluginCapability`)

| Capability | 典型 Action & Params | 返回 / 说明 |
| --- | --- | --- |
| `clipboard` | `read` (`{}`)、`write` (`{"text":"..."}`) | 读写系统剪贴板文本（脱敏保护） |
| `ocr` | `recognize` (`{"imagePath":"/abs/path.png"}`) | 复用 `VisionService` 离线识别中英文字与条码 |
| `everythingSearch` | `search` (`{"query":"...","limit":20}`) | 复用 `EverythingIndex` 内存树按 DSL 检索文件 |
| `displayInfo` | `list` (`{}`) | 返回活跃显示器 `displayID`、当前模式与可用分辨率 |
| `systemControl` | `status`、`setVolume`、`setMute`、`setCaffeine` | 查询与安全调节系统音量/静音/防休眠状态 |
| `lumaLinkStatus` | `status` (`{}`) | 读取 LumaLink 监听状态（已脱敏，不含 PIN/Token） |

- 请求行格式（每连接单行 JSON + 换行，如 `/usr/bin/nc -U "$LUMAKEY_BRIDGE_SOCK"`）：
  `{"token":"$LUMAKEY_BRIDGE_TOKEN","capability":"displayInfo","action":"list","params":{}}`
- `mode`: `script`（纯文本 stdout）与 `view`（返回 `PluginViewPayload` JSON：`title`、`subtitle`、`badge`、`markdown`、`metrics`、`items`，非 JSON 平滑降级纯文本）；精选商店内置 5 款脚手架模板（含 `host-snapshot`）。

## 三、全 App 权限审计矩阵与开发者套件

- **权限全景清单 (`PluginPermissionAudit`)**：汇总全部 11 项系统 TCC、内核采样与宿主桥接权限，列出每项权限当前被哪些 `BUILTIN` / `EXT` 插件声明及授权状态，并在底部独立归集显式声明 `[]` 的纯沙盒插件；设置中心「权限清单」Tab 支持按需筛选与一键跳转对应插件或系统隐私设置。
- **内置工具与短语**：`LumakeyCore` 同时内置零子进程 `DevToolkitEngine` 与 `SnippetStore`。

## 四、原生 Stdio MCP 服务器 (`lumakey-mcp` v0.3.0)

`lumakey-mcp` 基于零依赖换行分隔 JSON-RPC 2.0（支持 `--plugins-dir <path>`）。

- **`initialize` 引导 (`instructions`)**：明确声明 Lumakey 非后台常驻服务器架构、禁止编写 `launchd`/死循环守护进程、创建插件前先阅读 `lumakey://specs/plugin-v3` 与列出已有内置/外部插件、强制声明 `capabilities` 并在生成后调用校验与运行测试。
- **暴露资源 (`resources`)**：`lumakey://specs/plugin-v3`（主规范，并保留 `plugin-v1` / `plugin-v2` 兼容资源）。

### 暴露的工具 (`tools`)

| 工具名 | 必选 / 关键参数 | 作用 |
| --- | --- | --- |
| `lumakey_list_plugins` | `includeBuiltin`（可选，默认 `true`） | 一并返回 `BUILTIN` 原生插件与外部扩展插件的启用、声明权限及授权状态，防止重复造轮子 |
| `lumakey_app_permissions` | `onlyUsed`（可选） | 返回全 App 权限审计矩阵：每项权限由哪些插件声明与使用，以及纯沙盒 (`[]`) 插件列表 |
| `lumakey_scaffold_plugin` | `id`, `name`, `keywords`, `capabilities`（必选） | 安全生成 `plugin.json` 与可执行 `run.sh`（声明能力时自动生成 Host Bridge `nc -U` 示例模板） |
| `lumakey_install_starter_plugin` | `id`, `overwrite` | 一键安装官方脚手架模板（`sys-ip-dns`、`quick-hash-uuid`、`port-killer`、`shell-note`、`host-snapshot`） |
| `lumakey_validate_plugin` | `id` | 校验 `capabilities` 必选声明、未知权限名、`builtin-` 保留前缀、脚本权限与防路径逃逸 |
| `lumakey_run_plugin_test` | `id`, `query`, `clipboardText`（可选） | 执行内置或外部插件测试（自动拉起临时 Host Bridge），返回 `exitCode`、`isStructuredView`、`stdout`、`stderr` |
| `lumakey_set_plugin_enabled` | `id`, `enabled` | 启停外部或 `BUILTIN` 插件（停用 `BUILTIN` 即刻回收监听器与事件回调） |
| `lumakey_remove_plugin` | `id` | 移除外部扩展插件目录与状态（禁止删除 `builtin-*` 原生插件） |
