# 本地开发、代码签名与对外分发指南

## 环境要求

- **硬件与系统**：Apple Silicon (`arm64`) Mac，运行 `macOS 14.0+`。
- **工具链**：Apple Swift 6 工具链（Command Line Tools 或 Xcode 均可，`xcode-select -p` 无需完整 Xcode 即可编译全部目标）。
- **外部依赖**：**零第三方 Swift 包依赖**。如宿主机已通过 Homebrew 安装 `ntfs-3g` 或 `ffmpeg`/`ffprobe`，应用会自动探测其状态。

## 目录结构

```text
Lumakey/
├── Package.swift                      # Swift 6 九目标分层清单 (Foundation/Search/Media/System/Core + App/MCP + Tests/Check)
├── LICENSE                            # MIT 开源许可证
├── CONTRIBUTING.md                    # 外部贡献规范与模块依赖边界红线
├── .github/workflows/                 # CI (arm64 验证)、GitHub Pages 自动部署与 Release DMG 发布流
├── apps/macos/
│   ├── Info.plist                     # macOS arm64 应用包元数据 (app.lumakey.macos, LSUIElement = true)
│   └── Lumakey.entitlements           # Hardened Runtime 与 Apple 公证所需最小权限声明
├── Sources/
│   ├── LumakeyFoundation/             # 零上层依赖基础库（本地化、双主题、签名检查、双轨密钥库、进程监管）
│   ├── LumakeySearch/                 # 全盘索引（EverythingIndex / LMKYIDX3 SHA-256 快照）与安全文件操作
│   ├── LumakeyMedia/                  # 多屏几何与分片 DPI 截图合成、离线 Vision OCR、视频零拷贝兼容与纯 Swift Markdown 解析
│   ├── LumakeySystem/                 # Mach/IOKit 系统监控、网络流量去向、物理鼠标平滑与热键冲突探测
│   ├── LumakeyCore/                   # 插件引擎（Seatbelt 沙箱、自由窗口规格、宿主 TCC 代理、系统通知）、LumaLink、Backup v2 与全局搜索编排
│   ├── Lumakey/                       # SwiftUI + AppKit 菜单栏常驻、双内置主题界面、WKWebView 自由浮窗与 SCStream 区域录屏
│   └── LumakeyMCP/                    # 原生 stdio JSON-RPC 2.0 MCP 服务 (lumakey-mcp)
├── Tests/
│   ├── LumakeyTests/                  # 标准 Swift Testing 单元测试与检索/内存延迟基准套件 (swift test)
│   └── LumakeyCheck/                  # 全链路系统自检与 lumakey-mcp 真实子进程联调
├── plugin-demo/                       # 官方示例插件商店（8 款旗舰插件源码、package-store.sh 与 lumakey-registry.json）
├── site/                              # 产品介绍页（3D WebGL2 体验主页 + 2D 图文详解实验台）
├── scripts/
│   ├── check-docs.py                  # 文档索引覆盖与断链/锚点检查
│   ├── verify-macos.sh                # arm64 环境、300 行 Clean Code、编译与校验总门禁
│   ├── generate-icon.swift            # 生成 Retina 应用图标集
│   ├── build-macos.sh                 # 构建 dist/Lumakey.app（默认分发/开源社区签名模式，支持 --local-dev 本机开发证书）
│   ├── package-dmg.sh                 # 将 dist/Lumakey.app 封装为签名压缩 DMG 与 .sha256
│   ├── release-macos.sh               # 一键对外分发构建 + Developer ID 签名 + notarytool 公证与 stapler 钉票
│   ├── install-macos.sh               # 打包并部署到本机 /Applications/Lumakey.app（支持 --skip-build）
│   ├── resign-local-app.sh            # 面向 DMG 用户的本机固定重签脚本（免 $99 证书跨更新延续本机权限）
│   └── setup-local-signing.sh         # 仅限开发者本机自用：生成本地证书免除本机调试重复授权
└── docs/                              # 设计与工程文档
```

## 三种构建与分发模式

### 1. 正式对外分发（Developer ID + Hardened Runtime + Apple 公证）

面向其他 macOS 用户分发时（零 Gatekeeper 拦截弹窗、跨版本升级自动保留「辅助功能 / 屏幕录制」授权）：

```bash
# 首次在钥匙串保存 Apple 公证凭据（只需执行一次）
xcrun notarytool store-credentials "lumakey-notary" \
  --apple-id "<YOUR_APPLE_ID>" \
  --team-id "<YOUR_TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"

# 一键执行 --distribution 构建、Hardened Runtime 签名、DMG 封装、Apple 公证与离线票据装订
APPLE_NOTARY_PROFILE="lumakey-notary" bash scripts/release-macos.sh
```

`scripts/release-macos.sh` 会强制开启 `--distribution` 模式：**绝不混入个人本机自签或开发证书**，自动使用钥匙串中的 `Developer ID Application` 证书由内向外附加 `--options runtime --timestamp --entitlements apps/macos/Lumakey.entitlements` 签名，提交 `notarytool` 并通过 `stapler` 将离线公证票据钉入 `dist/Lumakey.dmg`。

### 2. 开源免证书分发（暂无 $99/年 Apple Developer 账号时）

若当前机器未安装 `Developer ID Application` 证书，直接运行：

```bash
bash scripts/release-macos.sh
```

脚本会自动产出不含任何个人机器信息的干净通用包 `dist/Lumakey.dmg`（附带 `.sha256` 校验文件）。其他用户下载拖入 `/Applications` 后，首次右键点击「打开」（或在「系统设置 › 隐私与安全性」点击「仍要打开」，或通过 Homebrew Cask `--no-quarantine` 安装）即可正常使用。

### 3. 开发者本机编译与自用安装

```bash
# 校验全部文档与内部链接
python3 -B scripts/check-docs.py

# 执行完整静态检查、Clean Code 300 行检查、Swift 编译与测试集
bash scripts/verify-macos.sh

# 打包并安装到本机 /Applications/Lumakey.app（如已构建可加 --skip-build 秒级同步）
bash scripts/install-macos.sh
```
