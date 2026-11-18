# 当前实现状态

本文件仅记录当前仓库中已通过编译、单测与集成校验的**真实当前能力**（遵循单一事实来源原则，不堆叠历史版本流水账）；后续演进规划见 [版本路线图](ROADMAP.md)。

## 1. 核心架构与工程门禁

- **纯原生 Swift 6 无环模块分层**：全仓采用 `macOS 14.0+` / `arm64` 编译（`.swiftLanguageMode(.v6)`），**零第三方依赖**，划分为 `LucentFoundation` → `LucentSearch` / `LucentMedia` / `LucentSystem` → `LucentCore` → `Lucent` / `lucent-mcp` 单向无环（DAG）架构，由 `scripts/verify-macos.sh` 静态拦截越界反向导入与单文件 `≤ 300` 行上限。
- **双生液态玻璃与实时双语**：内置浅色「凝霜留白 (`Pure Frost`)」与深色「霓彩流光 (`Prism Pulse`)」两套动态令牌主题，配合简体中文 / English 免重启全局热切换；品牌视觉由 `LucentFoundation.BrandIconRenderer` 单一真源统一驱动运行时矢量位图与构建期 `AppIcon.icns`。
- **空闲内存自洁生命周期**：主悬浮窗恒定锁定 `880 × 544` 零跳动尺寸，收起 `30s` 后自动释放视图树；全盘索引冷启动仅执行 `O(1)` 4 KB 快照头探测，空闲 `90s` 或收到系统内存压力信号时自动卸载内存节点与缩略图缓存；全部二级窗口关闭时置空 `contentView` 并回收堆页；所有悬浮监控、菜单栏实时读数与插件快捷按钮默认全关。

## 2. 统一快捷中枢 (`⌥Space`) 与可定制启动面板

- **模块化多场景启动页 (`home-layout.json`)**：支持最多 8 套场景 Profile 与 4 套官方预设切换、一键撤回编辑，自由编排 Bento 大磁贴（`2/3/4` 列）、混合高频坞（`8/16` 格，混排本机应用、插件、目录与协议书签）、最多 6 组命名胶囊架及可隐藏探索提示条，并打通搜索候选右键「钉上主页」与 `lucent-mcp` 零轮询热刷新。
- **并发全搜与内置效率引擎**：
  - **应用启动与智能排序 (`AppUsageService`)**：融合前台活跃时长、启动频次 `log2` 加权、时间衰减与中文多音字拼音首字母检索；
  - **全盘与外置盘秒搜 (`EverythingIndex` + `LCNTIDX3`)**：基于 POSIX `opendir`/`readdir` 多卷并发扫描、带尾部 `SHA-256` 与无环父指针校验的 `mmap` 二进制快照、`FSEvents` 实时增量同步及用户自定义排除路径；
  - **计算、10 维单位换算与离线开发工具箱 (`UnitAndCommandEngine` + `DevToolkitEngine` + `SnippetStore`)**：覆盖算式/百分比/科学函数、10 类中英自然单位换算、`;` 动态模板短语，以及离线时间戳、UUID、Base64/URL、JWT、JSON、哈希、色值与二维码生成；
  - **富媒体剪贴板历史 (`ClipboardMonitor`)**：支持文本、`#HEX`/`rgb` 色值、图片、GIF、视频与多文件固化快照，自动过滤密码管理器隐私标记与高危明文私钥，支持回车粘贴回原窗口、15 步删除撤回、容量/过期策略、应用黑名单及 `0600` 收藏项持久化。

## 3. 多显示器捕获、录屏与按需原生工具窗

- **逐屏原生 DPI 截图标注、离线识字与钉图 (`⌥A` / `⌥O`)**：基于 `MultiDisplayLayout` 与 `ScreenCaptureKit` 实现跨屏混合 DPI 无损分片捕获、独立窗口无遮挡圆角抠取（支持去阴影）、10 种实时标注工具、放大镜 `#HEX` 取色、`1:1` 悬浮穿透钉图 (`PinWindowController`)，以及绑定 CPU 亚秒级响应的离线 `Vision` 中英 OCR / 条码识别 (`OCRResultWindowController`)。
- **零依赖流式区域 GIF 录屏 (`⌥G`)**：基于 `SCStream` + `ImageIO` 实现窗口吸附或跨屏选区 GIF89a 动图录制，支持静止帧差值压缩、灵动岛悬浮 HUD 控制与即录即粘。
- **物理鼠标平滑滚轮 (`MosMouseService`)**：独立区分外接物理鼠标与苹果触控板，仅对外接鼠标应用 `120Hz` 平滑插值、方向反转、`⇧` 横向滚动、`⌥` 加速与应用级排除；未开启或静止时零事件回调开销。
- **按需独立窗口与双栏文件工作台 (`⌥E` / `⌥M` / `⌥N`)**：提供零 `WKWebView` 原生 Markdown/代码阅读器、只读看图窗、支持 `'hev1'` 零拷贝硬解与同目录连播的 4K 影院播放器、双栏多选框选与只读 NTFS 护航的文件工作台、贴边自适应系统脉搏监控窗 (`⌥M`)、免 Root `nettop` 进程网络去向监控 (`⌥N`) 与分桶缓存清理。

## 4. 插件生态 (`Plugin v3.7`)、快捷脚本库与 AI 协议桥 (`lucent-mcp`)

- **纵深沙箱与高熵密钥保险箱 (`LCNTVLT2`)**：外部插件与快捷脚本统一经 `/usr/bin/sandbox-exec` 动态生成 Apple Seatbelt 策略隔离运行（净化宿主环境变量，无条件封锁系统钥匙串与宿主 `.vault`），通过 `ProcessSupervisor` 无死锁双管道与进程组精确取消监管；敏感凭据由 `LocalSecretVault` 采用 256-bit `AES-GCM` 双轨密封落盘；系统 TCC 权限遵循「宿主统一代申、单次 `0700` UDS 令牌桥接」并纳入全景权限审计矩阵。
- **原生卡片、置顶面板与自由画布挂件**：支持零前端自动生成原生设置表单、结构化交互卡片、`lucent://panel/<id>` 独立置顶轮询面板，以及授权 `window` / `floatingWindow` 后的沙盒化 `WKWebView` 透明桌面挂件（含网络规则拦截、坐标记忆与环境变更实时广播）。
- **单文件双向同步快捷脚本库 (`Quick Scripts`)**：支持 Zsh、Bash、Python 3、AppleScript、Swift 及任意 `#!` 自定义 Shebang 脚本，与 `@lucent.*` 头部注释双向同步，支持专属安全 SVG 图标、独立热键与 5 种输出反馈。
- **智能商店订阅、备份同步与内置 MCP 服务**：
  - 单输入框自动嗅探 GitHub 仓库、商店 `lucent-registry.json` 或 `.zip` 包，强制校验 `SHA-256` 与权限升级差异，附带 `plugin-demo/` 7 款原生 Swift 6 官方插件与 3 款内置精选模板；
  - 支持应用与插件更新检查、含 `LZFSE` 压缩与可选口令密钥迁移的 `.lucentbackup` v2 归档及 HTTPS WebDAV 云端自动轮转同步；
  - 安装包内置零外部依赖 `lucent-mcp` 二进制，暴露 4 份规范资源与 20 项工具供 AI 客户端直接创建脚本、脚手架开发插件与编排启动面板。

## 5. 当前已知运行约束

- 初次启用物理鼠标平滑、全局输入拦截或跨应用粘贴回填需在系统设置授予「辅助功能」权限；初次使用截图标注、离线识字或 GIF 录屏需授予「屏幕录制」权限（无商业公证证书环境下可通过 `scripts/resign-local-app.sh` 绑定本机签名免除升级重复授权）。
- 标准自动化验证由 `python3 -B scripts/check-docs.py`、`swift test --arch arm64`（`LucentTests` 单元与性能基线）及 `bash scripts/verify-macos.sh`（模块边界、行数门禁与 `lucent-mcp` 真实子进程往返）共同保障。
