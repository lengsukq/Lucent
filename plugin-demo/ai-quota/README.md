# AI 额度雷达 · CLI 用量与 API 余额面板 (`ai-quota` v1.2.0)

面向 **Lumakey Plugin v3.6+** 打造的开发者高频 AI 编程工具实时额度与账户余额监控插件，同时演示**无边框透明玻璃自由悬浮挂件 (`floatingWindow` + `window.lumakey` 双向 SDK)**、**默认置顶监控小窗**与**系统原生通知横幅**：

- **OpenAI Codex CLI (`codex`)**：通过本机 `codex app-server` JSON-RPC (`account/rateLimits/read`) 实时读取 `5h` 与 `7d` 速率窗口余量及重置倒计时，并聚合 `~/.codex/sessions` 今日会话与 Token 消耗。
- **Claude Code (`claude`)**：通过本机 `claude -p /status --no-session-persistence` 与状态栏配额缓存查看 `5h / 7d` 窗口利用率，并自动汇总 `~/.claude/projects` 今日 Token 消耗与 Prompt 缓存命中率。
- **Google Antigravity CLI (`agy`)**：实时调用本机 `agy -p /usage`（自动关闭后台自更新阻塞）解析 Gemini 与共享模型池剩余百分比，并统计 `~/.gemini/tmp` 今日会话 Token。
- **DSH · DeepSeek Harness (`dsh`)**：探测本机 `dsh` CLI 与本地运行档案，自动聚合 `dsh-usage` 今日调用次数、Token 总量、缓存命中率与预估花费。
- **DeepSeek 官方账户余额 (`deepseek`)**：在插件独立设置页（`⌘,`）填入 `DeepSeek API Key`（支持多账号逗号分隔，由宿主 `LMKYVLT2` `0600` `AES-GCM` 保险箱加密托管），实时请求 `GET https://api.deepseek.com/user/balance` 展示 CNY (`¥`) / USD (`$`) 总余额、充值余额与赠送金。

## 核心工程特性

1. **无边框透明玻璃自由挂件 (`--custom-hud` / `ui/widget.html`)**：声明 `capabilities: ["clipboard", "floatingWindow", "notifications"]`，通过 `window.lumakey` 双向 JS Bridge 调用 `--json` 后端实时渲染 4 路 SVG 环形进度仪表、渐变进度条、紧凑折叠态（`lumakey.window.resize`）、透明度滑块（`lumakey.window.setOpacity`）与 120Hz 原生拖拽（`data-lumakey-drag`），关闭窗口即销毁视图与定时采样。
2. **独立置顶悬浮监控窗 (`--float-panel` / `lumakey://panel/ai-quota`)**：同时保留宿主原生结构化卡片悬浮小窗，支持 `15s ~ 300s` 自动轮询或暂停/手动刷新。
3. **后台静默刷新 + macOS 原生通知横幅 (`effect.notification` / `notifications.send`)**：由宿主统一代申 macOS 通知权限，一键发送最新余量与余额横幅摘要。
4. **严格只读与零密钥落盘**：不读取或修改任何本地 CLI 的登录凭证文件；`DeepSeek API Key` 仅在进程内存中放入 HTTPS `Authorization` 头，绝不写入命令行参数、`PluginData` 快照或 `search-index.json`。

## 本地验证

```bash
python3 -B plugin-demo/ai-quota/test_ai_quota.py
```
