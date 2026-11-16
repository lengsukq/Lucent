# 本地开发、代码签名与对外分发指南

## 环境要求

- **硬件与系统**：Apple Silicon (`arm64`) Mac，运行 `macOS 14.0+`。
- **工具链**：Apple Swift 6 工具链（Command Line Tools 或 Xcode 均可，`xcode-select -p` 无需完整 Xcode 即可编译全部目标）。
- **外部依赖**：**零第三方 Swift 包依赖**。如宿主机已通过 Homebrew 安装 `ntfs-3g` 或 `ffmpeg`/`ffprobe`，应用会自动探测其状态。

## 目录结构

```text
Lumakey/
├── Package.swift                      # Swift 6 四目标清单 (LumakeyCore / Lumakey / lumakey-mcp / LumakeyCheck)
├── apps/macos/
│   ├── Info.plist                     # macOS arm64 应用包元数据 (app.lumakey.macos, LSUIElement = true)
│   └── Lumakey.entitlements           # Hardened Runtime 与 Apple 公证所需最小权限声明
├── Sources/
│   ├── LumakeyCore/                   # 无 UI 强依赖的核心引擎与系统服务封装
│   ├── Lumakey/                       # SwiftUI + AppKit 菜单栏常驻与双内置主题界面
│   └── LumakeyMCP/                    # 原生 stdio JSON-RPC 2.0 MCP 服务 (lumakey-mcp)
├── Tests/
│   └── LumakeyCheck/                  # 确定性校验程序与 MCP 真实子进程测试
├── scripts/
│   ├── check-docs.py                  # 文档索引覆盖与断链/锚点检查
│   ├── verify-macos.sh                # arm64 环境、300 行 Clean Code、编译与校验总门禁
│   ├── generate-icon.swift            # 生成 Retina 应用图标集
│   ├── build-macos.sh                 # 构建 dist/Lumakey.app（支持本机开发与 --distribution 正式分发模式）
│   ├── package-dmg.sh                 # 将 dist/Lumakey.app 封装为签名压缩 DMG 与 .sha256
│   ├── release-macos.sh               # 一键对外分发构建 + Developer ID 签名 + notarytool 公证与 stapler 钉票
│   ├── install-macos.sh               # 打包并部署到本机 /Applications/Lumakey.app（支持 --skip-build）
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
