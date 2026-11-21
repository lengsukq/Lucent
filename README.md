# <img src="site/assets/icon.svg" alt="Lucent 3D Icon" width="44" height="44" align="top" /> 流光 Lucent

> **在线体验页**：[3D 沉浸式主页](https://lengsukq.github.io/Lucent/) ｜ [2D 图文详解与交互实验台](https://lengsukq.github.io/Lucent/overview.html) ｜ **官方插件库**：[`plugin-demo/`](plugin-demo/README.md) ｜ **技术文档**：[文档总览](docs/INDEX.md)

**一触流光，用完即焚 —— 专为 Apple Silicon Mac 打造的轻巧、可深度定制的原生快捷效率中枢。**

- **对日常用户来说**：按一下 `⌥Space`，找软件、搜电脑与移动硬盘里的文件、翻剪贴板历史、算账换算、多屏截图标注贴图、录 GIF 动图、一秒离线识字、让外接鼠标滚轮像触控板一样顺滑——**一个只有 10 MB 左右的小软件就能全部搞定**；用完切回工作后自动释放内存，绝不在后台偷偷拖慢电脑。
- **对极客与进阶玩家来说**：从 **`⌥Space` 启动面板的四分区布局与多场景主页**、**单文件双向同步的快捷脚本库（支持自定义 Shebang 与专属 SVG 图标）**、**顶部菜单栏条目**、**全链路静默热键与唤醒词权重**，到 **Plugin v3.7 自由画布透明桌面悬浮窗** 与 **内置 21 项工具的 `lucent-mcp` AI 协议桥**，每一处都支持精细拆装与一句话 AI 定制；底层采用 **100% 纯原生 Swift 6、零第三方依赖、9 模块单向无环（DAG）架构与单文件 `≤ 300` 行门禁**。

---

## 高度自定义：从启动面板到菜单栏，长成你最顺手的样子

我们不想把所有人塞进同一套死板拥挤的界面里。在 Lucent 中，**看见什么、怎么排列、按哪个键触发，全部由你决定**：

### 1. 全新「启动面板自定义」—— 像搭积木一样布置你的 `⌥Space` 主页

打开 `⌥Space` 但还没打字时的默认启动面板，现在可以完全按你的工作习惯自由编排（配置存于 `home-layout.json`，支持跨设备加密备份同步）：

- **四大分区自由开关、上下调序与密度调节**：
  - **Bento 大磁贴区**：可选 `2 列宽卡 / 3 列标准 / 4 列紧凑`，适合放每天最常用的截图识字、主力自制插件或核心网页；
  - **混合高频坞（Omni Dock）**：可选 `1 排 8 格 / 2 排 16 格`，支持将**本机 App、自制插件、常用网页书签、本地文件夹**混排在一起，并可选「手动钉选优先 + 智能高频补位」或「纯手动白名单」；
  - **分组书签与胶囊架**：最多可新建 **6 组自定义命名胶囊架**（例如「AI 常用」「团队文档」「本地开发端口」），把常点链接与插件子功能分类排好；
  - **探索提示与底栏入口**：熟悉操作后可一键隐藏提示词条与重复底栏按钮，还你一片干净留白。
- **搜索结果右键「一键钉上主页」**：搜到任何软件、文件目录、书签链接、内置动作或插件子功能，点一下右键就能直接钉进磁贴、高频坞或任意书签架；每个条目都能**单独修改标题、图标与强调色**（网页书签还支持指定用哪款浏览器打开，并支持 `vscode://`、`cursor://`、`obsidian://`、`notion://` 等开发与笔记协议），改乱了随时点 **「撤回修改」** 一键恢复。
- **多场景主页 Profile 与 4 套官方预设**：内置 **「均衡默认 / 极简纯搜 / 开发者工作台 / 应用与书签中心」** 4 套预设，还能自建「工作模式」「专注写作」「周末娱乐」等多套主页方案一键切换。
- **甚至不用手动排 —— 对 AI 说一句话帮你布好局**：`lucent-mcp` 已内置主页编排工具（`lucent_get_home_layout` / `lucent_update_home_layout` / `lucent_upsert_home_item`），直接对 Claude Code 或 Cursor 说一句 *“帮我配一套极简开发启动面板，放好双栏文件台、端口清理和 GitHub 书签架”*，运行中的面板即刻热刷新生效。

### 2. 菜单栏、快捷键、唤醒词与主题全维度可调

- **顶部状态栏菜单瘦身定制**：提供「精简核心 / 效率常用 / 完整全量」3 套预设，支持逐项勾选显隐、上下调序、将低频维护项折入二级子菜单、无活跃窗口时自动隐藏清理项，以及 4 款状态栏图标样式。
- **全键盘流与不改源码的个性化覆盖（`PluginUserOverrides`）**：10 项核心全局热键与**每一个插件、每一条细分动作**都能独立录制全局快捷键（自带三层热键冲突检测；开启静默模式后按下热键直接在后台瞬时完成，不打断当前全屏应用）。无需触碰插件源码，即可随时修改唤醒关键词、调整搜索排序权重、或单独决定哪些子命令混入全局搜索。
- **双生液态玻璃外观 × 中英免重启切换**：内置清爽通透的浅色 **「凝霜留白 Pure Frost」** 与深邃棱镜质感的深色 **「霓彩流光 Prism Pulse」**，搭配 **简体中文 / English** 实时切换，主题与语言会自动同步给所有已启用插件。

### 3. 一句话 AI 十秒造脚本 / 插件 & 自由画布桌面挂件（`Plugin v3.7` + `Quick Scripts`）

- **不会写代码也能做自己的小工具**：安装包直接内置 `lucent-mcp` 服务（21 项标准工具），连接 Claude Code、Cursor、Codex 或 Gemini CLI 后，只需用日常语言描述需求（比如压缩图片体积、查内部工单、看服务器状态、清理指定端口与目录），AI 既能秒建带中英双语名与 **`64×64` 专属 `<svg>` 图标**的单文件快捷脚本（`Quick Scripts`），也能在十秒左右自动完成多视图插件脚手架生成、静态校验与沙箱实测，实时热重载出现在 `⌥Space` 里。
- **既能零前端出原生卡片，也能做无边框透明桌面挂件**：插件只需一份 `plugin.json` 就能自动生成带滑块、密钥框、路径选择器的原生设置页；若需要高自由度界面，还可申请 `window` / `floatingWindow` 权限渲染自定义 HTML/CSS/Canvas 窗口、置顶透明玻璃挂件（支持 `120Hz` 无边框拖拽、点击穿透与位置记忆，关窗即释放内存）。
- **单地址框智能商店订阅（11 款官方插件全原生 Swift 零依赖）**：在「设置 › 插件中心」粘贴任意 GitHub 仓库链接、子目录、商店 JSON 或 `.zip` 插件包地址，自动嗅探识别并校验 64 位 `SHA-256` 与权限边界；11 款官方精选插件与 3 款起始模板均预编译为原生 `arm64` Swift 二进制（无需安装 Python 3），升级插件完整保留你的自定义热键、唤醒词与加密凭据。

---

## 日常开箱即用的五大能力（不装任何插件也足够顺手）

### 1. 一个搜索框搞定高频日常（`⌥Space`）
不用记繁琐前缀，呼出直接打字：
- **秒开软件 & 搜全盘与移动硬盘文件**：支持中文双音字与拼音首字母，插上外置硬盘也能秒搜文件；
- **贴心剪贴板历史**：复制过的文字、`#HEX` 色值、图片、GIF 和文件随时找回；回车直接粘贴回刚才的窗口，误删支持 **15 步撤回**，并自动跳过密码管理器的敏感内容；
- **算账、换算、快捷脚本与离线开发小工具**：直接输入算式、百分比或进制换算，中英文自然换算长度、重量、存储容量、温度、时间等 10 类单位；输入 `!` 秒跑单文件快捷脚本库（支持 Zsh / Python / AppleScript / Swift / 自定义 Shebang 与 `Scripts/` 目录双向同步），输入 `;` 展开快捷短语，离线生成二维码、UUID、解析时间戳或 JWT；
- **稳稳的肌肉记忆**：面板恒定锁定 `880 × 544` 不跳变，中文拼音选词不误触回车，后台索引刷新绝不抢走你正选中的那一行。

### 2. 多显示器一样清晰的截图标注、滚动长截图、录屏与离线识字（`⌥A` / `⌥G` / `⌥O`）
- **高清截图、矢量二次编辑、长截图与钉屏贴图（`⌥A`）**：多块不同分辨率显示器拼接也能逐屏原画质框选；支持窗口圆角无遮挡抠取（可一键去阴影）与无障碍子控件下钻吸附；内置 11 种矢量标注工具（曲线箭头、带引线序号、局部高斯模糊、正片叠底荧光笔、实时马赛克、放大镜按 `C` 取色等）与 100 步撤销二次编辑，支持手动滚动长截图自动拼接，还能把截图直接**钉在屏幕最上层**（按 `T` 开启半透明穿透、按空格原地二次标注）；
- **轻巧区域 GIF / MP4 录屏（`⌥G`）**：框选区域或窗口直接录成灵巧 GIF 动图或高清 MP4 视频，自动压缩静止帧，贴文档、发聊天即录即走；
- **一秒离线识字（`⌥O`）**：框选屏幕上的中英文或二维码，不联网直接在本地提取复制，还能一键把识别出的文字交给翻译或笔记插件接着处理。

### 3. 外接普通鼠标也能像苹果触控板一样丝滑
- 独立识别物理鼠标与触控板：**只为外接鼠标开启 120Hz 平滑滚轮与独立滚轮方向反转，完全保留苹果触控板原本的自然滚动手感**；支持按住 `Shift` 横向滚、按住 `Option` 加速滚，以及按应用单独排除。

### 4. 按需呼出、关窗即释放内存的实用工具箱
- **清爽读文档 / 无损看图 / 4K 播片**：纯原生窗口秒开 Markdown 笔记（带目录大纲）、大图与 4K HEVC 视频（支持 `520×300` 小窗置顶与同目录连播），关窗立刻归还全部内存；
- **双栏文件整理台（`⌥E`）**：整理资料时按需呼出，支持框选、跨栏拖拽复制移动、批量重命名预检与安全移入废纸篓，遇到默认只读的 NTFS 移动硬盘自动护航防误写；
- **芯片脉搏 & 软件网速透视（`⌥M` / `⌥N`）**：需要时查看芯片大小核负载、整机实时功耗（W）以及每个应用当前的上下行网速与联网去向，顺手安全清理应用缓存；
- **11 款官方精选插件（[`plugin-demo/`](plugin-demo/README.md)）**：
  - [`file-shelf`](plugin-demo/file-shelf/README.md)：文件中转站（原生液态玻璃边缘吸附托盘，支持跨屏拖拽暂存、右键动作与跨重启恢复）
  - [`audio-presets`](plugin-demo/audio-presets/README.md)：一键音频组合（无边框液态玻璃控制台，支持设备卡直切与 Core Audio 失败回滚）
  - [`translate-hub`](plugin-demo/translate-hub/README.md)：流光译站（跨应用划词 / OCR 截图翻译、多引擎与本地 Ollama 对照、朗读与生词本导出 Anki）
  - [`browser-hub`](plugin-demo/browser-hub/README.md)：三端书签与历史中枢（无锁秒搜 Safari、Chrome 多配置档与 Edge 书签历史）
  - [`quick-remind`](plugin-demo/quick-remind/README.md)：闪电提醒（`10m 喝水` 自然语言倒计时与番茄钟，直通系统原生提醒事项零后台守护）
  - [`mac-pilot`](plugin-demo/mac-pilot/README.md)：桌面中控台（音量/防休眠、16 项系统设置秒达、安全退盘与访达原地新建文件）
  - [`screen-shield`](plugin-demo/screen-shield/README.md)：状态屏遮罩（擦键盘屏幕防误触黑屏、编译运行中防误碰保护屏，长按 `Esc` 2 秒解锁）
  - [`lumalink-companion`](plugin-demo/lumalink-companion/README.md)：LumaLink 远程控制伴侣（配对二维码、网卡切换、远控物理防窥黑屏与 HiDPI 切换）
  - [`notion-bookmarks`](plugin-demo/notion-bookmarks/README.md)：Notion 加密书签箱（256-bit 加密托管凭据，一键静默速存剪贴板链接并同步本地秒搜）
  - [`antigravity-pulse`](plugin-demo/antigravity-pulse/README.md) / [`gold-monitor`](plugin-demo/gold-monitor/README.md)：自由画布桌面悬浮挂件示例（实时配额监控与金价行情 HUD）
- **整机一键备份与 WebDAV 云同步**：把启动面板布局、菜单栏配置、快捷键、自制插件与加密密钥打包成 `.lucentbackup` 文件或同步至坚果云 / NAS，换新 Mac 一键满血还原。

---

## 给极客与开发者的工程底牌

| 维度 | 核心实现细节 |
| --- | --- |
| **原生与包体积** | `macOS 14.0+` 纯 `arm64` 编译，**100% Swift 6 原生框架直连**（`ScreenCaptureKit` / `Vision` / `AVKit` / `Darwin Mach` / `CGEventTap`），**0 第三方外部包依赖**，安装包仅约 `10 MB` |
| **模块化与 Clean Code** | 9 大单向无环（DAG）Target 分层，自动化门禁每次构建强校验模块依赖边界、文档死链与**单 `.swift` 源文件 `≤ 300` 行硬上限** |
| **低延迟与自洁内存** | `LCNTIDX3` 零拷贝 `mmap` 快照 + `FSEvents` 实时增量索引；主面板收起 `30s` 自动销毁视图层级，文件索引空闲 `90s` 或内存压力下自动卸载堆页；默认开启的常驻桌面挂件数为 `0` |
| **纵深安全与隐私** | 外部插件由 `/usr/bin/sandbox-exec` 动态生成 `Seatbelt` 内核沙箱隔离运行（默认阻断未声明网络与子进程，硬性拉黑系统钥匙串与宿主保险箱）；宿主桥接采用 `0700` 临时目录一次性 48-bit 令牌；敏感密钥由 `LCNTVLT2` 双轨 `256-bit AES-GCM` 加密落盘；系统 TCC 权限由 `PluginHostTCCBroker` 统一代申并纳入 21 项全景权限审计矩阵 |
| **AI 协议桥 (`lucent-mcp`)** | 应用内自带零依赖 Stdio JSON-RPC 2.0 服务（`/Applications/Lucent.app/Contents/MacOS/lucent-mcp`），内置 `plugin-v3`、`plugin-store-v1`、`home-layout-v1`、`scripts-v1` 四份规范资源与 **21 项工具**（覆盖快捷脚本创建与 SVG 图标绘制、插件脚手架、静态契约校验、沙箱实跑、商店打包、启动面板实时编排及按需授权只读文件秒搜） |

---

## 我们坚持不做的事

- **不做强行开启的臃肿全家桶**：所有悬浮监控窗、菜单栏实时读数与插件快捷按钮在刚安装时**全部默认关闭**，需要哪项开哪项；
- **不做重型文件大管家或音视频剪辑器**：`⌥Space` 永远是轻快第一入口，双栏文件台与阅读/播片窗均为按需借用、关窗即净；
- **不在后台装常驻扫盘守护进程，也不冒险强写脏 NTFS 盘**：拒绝 `launchd` 开机后台偷跑，遇到带脏标记的 NTFS 移动硬盘严格只读护航。

---

## 安装与使用

### 普通用户三步安装

1. 前往 [Releases](https://github.com/lengsukq/Lucent/releases/latest) 或 [产品介绍页](https://lengsukq.github.io/Lucent/overview.html#download) 下载最新 `Lucent.dmg`。
2. 打开安装包，将 **Lucent** 拖入 **「应用程序 (Applications)」** 文件夹。
3. 首次打开若遇到 macOS 提示未公证的开源应用，在 **「系统设置 › 隐私与安全性」** 底部点击 **「仍要打开」**（或右键点击应用图标选择「打开」），之后按 `⌥Space` 即可随时唤起。

#### 升级小技巧：一行命令绑定本机签名，后续更新免重复勾选权限

由于本项目免费开源发布、未购买每年 \$99 的 Apple 商业公证证书，直接替换新版 `.app` 时 macOS 可能会要求重新勾选一次「辅助功能 / 屏幕录制」权限。

只需在拖入新版 `Lucent.app` 后，打开「终端 (Terminal)」运行下面这一行命令（它会在**你的电脑本地**自动生成并复用一枚仅属于你本机的签名证书，同时清除隔离弹窗；软件设置中心也内置了一键引导）：

```bash
curl -fsSL https://raw.githubusercontent.com/lengsukq/Lucent/main/scripts/resign-local-app.sh | bash
```

- **首次运行**：按提示输入一次开机密码信任本机证书，再勾选一次系统权限；
- **今后升级**：除了直接使用软件内置的「自动安装更新并重签」外，手动替换 DMG 后重跑上面那行命令即可延续原有权限（已克隆仓库可直接执行 `bash scripts/resign-local-app.sh`；若系统旧记录异常可加 `-s -- --reset-tcc` 重置一次）；
- **插件热更新免授权**：所有官方与第三方插件均在应用外独立热更新，日常装卸或更新插件**完全不需要重新授权**。

<details>
<summary><strong>极客连接 AI（lucent-mcp）与开发者源码构建指南</strong>（点击展开）</summary>

### 一行命令接入 AI 助手（一句话造插件 / 排启动面板）

安装 `Lucent.app` 后，无需额外安装 Node 或 Python 依赖，直接将内置二进制接入你的 AI 客户端即可：

```bash
# Claude Code 一键注册
claude mcp add lucent /Applications/Lucent.app/Contents/MacOS/lucent-mcp
```

或在 Cursor / Codex / Gemini CLI 的 MCP 配置文件中加入：

```json
{
  "mcpServers": {
    "lucent": {
      "command": "/Applications/Lucent.app/Contents/MacOS/lucent-mcp"
    }
  }
}
```

### 源码构建、门禁校验与架构文档

更多工程设计细节请参阅：
- [文档总览](docs/INDEX.md) ｜ [产品定位与边界](docs/PRODUCT.md) ｜ [系统架构与 Clean Code 约束](docs/ARCHITECTURE.md)
- [液态玻璃设计规范](docs/DESIGN_SYSTEM.md) ｜ [插件系统与 MCP 接口规范](docs/PLUGIN_AND_MCP.md) ｜ [本地开发与分发指南](docs/DEVELOPMENT.md) ｜ [当前实现状态](docs/STATUS.md)

```bash
# 1. 文档与链接自检
python3 -B scripts/check-docs.py

# 2. 单元测试与性能延迟基准
swift test --arch arm64

# 3. 模块依赖边界、300 行 Clean Code、全目标编译与 MCP 往返联调校验
bash scripts/verify-macos.sh

# 4. 本地构建 .app (dist/Lucent.app)
bash scripts/build-macos.sh

# 5. 打包 DMG 并安装到本机 /Applications/Lucent.app
bash scripts/install-macos.sh

# 6. 构建对外公开发行版（支持 Developer ID 签名与 Apple 公证装订）
bash scripts/release-macos.sh
```

欢迎提交 Issue、插件或 PR，参与流程请参阅 [贡献指南](CONTRIBUTING.md)。

</details>

## 开源许可

本项目采用 [MIT License](LICENSE) 开源发布。

## 友情链接

- [LINUX DO](https://linux.do/) — 新的理想型社区（https://linux.do/）
