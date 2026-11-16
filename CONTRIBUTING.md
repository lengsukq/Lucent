# 参与贡献指南 (Contributing to Lumakey)

感谢关注并参与 **流光 Lumakey** 的开发与改进！为保持原生体验、安全边界与长期可维护性，提交 Issue 或 Pull Request 前请阅读以下规范。

## 1. 产品定位与能力边界

Lumakey 的核心定位是：**以键盘为核心、原生且低资源占用的 macOS Apple Silicon (`arm64`) 个人效率中枢**。

- **优先插件化扩展**：新增垂直工具、在线服务集成或低频工作流时，请优先基于 `plugin.json` v3 契约实现为外部扩展插件（参考 [插件系统与 MCP 接口规范](docs/PLUGIN_AND_MCP.md)），保持宿主主程序精简稳定。
- **严守不做清单**：不引入第三方 SwiftPM / CocoaPods 依赖，不嵌入 `WKWebView` 渲染常规界面，不部署 `launchd` 常驻后台守护进程，不做重型图像/视频剪辑工程（详见 [产品定位与边界](docs/PRODUCT.md)）。

## 2. 模块分层与架构红线

工程采用单向无环（DAG）Swift 6 模块分层，禁止反向依赖或跨层耦合（由 `scripts/verify-macos.sh` 自动审计）：

1. `LumakeyFoundation`：语言本地化、双主题配置、错误诊断、代码签名检测、双轨高熵密钥保险箱（`LocalSecretVault`）与进程监管器（`ProcessSupervisor`），**零上层业务依赖**。
2. `LumakeySearch`：POSIX/FSEvents 全盘文件索引（`EverythingIndex`）、带 SHA-256 校验的 `LMKYIDX3` 快照与安全文件工作台操作，仅依赖 `LumakeyFoundation`。
3. `LumakeyMedia`：截图合成、离线 Vision OCR、零拷贝 `'hev1'` 视频兼容与纯 Swift Markdown 解析，仅依赖 `LumakeyFoundation` 与 `LumakeySearch`。
4. `LumakeySystem`：Mach/IOKit 系统脉搏采样、进程网络去向、120Hz 物理鼠标平滑与三层全局热键冲突检测，仅依赖 `LumakeyFoundation`。
5. `LumakeyCore`：插件引擎（含 `sandbox-exec` 系统级 Seatbelt 沙箱隔离）、LumaLink 远控、WebDAV 备份与统一搜索编排。

代码与安全约束（详见 [AGENTS.md](AGENTS.md) 与 [系统架构与 Clean Code 约束](docs/ARCHITECTURE.md)）：
- 全部 Target 启用 Swift 6 严格并发模式（`.swiftLanguageMode(.v6)`）；
- `Sources/` 下单个 `.swift` 文件保持职责单一且不超过 **300 行**（不要为了凑行数机械横向切分共享可变状态，优先按独立值类型或模块边界解耦）；
- 严禁向外部插件子进程透传宿主完整环境变量，严禁绕过 `PluginSandboxProfileBuilder` 放行对 `.vault` 或系统钥匙串的访问。

## 3. 提交前必跑本地验证

任何代码或文档改动在提交 PR 前，必须在 Apple Silicon (`arm64`) 真机环境通过以下全部检查：

```bash
# 1. 文档索引与锚点断链检查
python3 -B scripts/check-docs.py

# 2. 标准 Swift Testing 单元测试与性能基准套件
swift test --arch arm64

# 3. 模块依赖边界、Clean Code、全目标构建与 lumakey-mcp 子进程集成校验
bash scripts/verify-macos.sh

# 4. 如涉及窗口、资源或签名逻辑，验证完整 Release .app 打包
bash scripts/build-macos.sh
```

## 4. Pull Request 提交流程

1. Fork 本仓库并基于 `main` 创建语义化分支（如 `feat/plugin-ux`、`fix/snapshot-bounds`、`refactor/search-module`）。
2. 为新增逻辑或修复的边界缺陷在 `Tests/LumakeyTests/` 中补充独立的 `@Test` 单元测试用例。
3. 若改动涉及架构、插件协议或已交付功能，同步更新 `docs/` 下对应的唯一事实文档（勿新建带日期的临时报告）。
4. 提交 PR 并附上清晰的改动动机、安全影响说明与本地验证输出摘要。

## 5. 开源许可

提交代码即表示您同意所贡献的内容按本仓库根目录的 [MIT License](LICENSE) 进行开源授权。
