# 流光译站 · 有道/苹果与多源大模型翻译 (`translate-hub`)

Lucent 官方翻译与词典插件（Plugin v3.7 · 原生 Swift 6 `arm64` 可执行程序 `bin/translate-hub`）：

## 支持的翻译引擎与自由展示控制

1. **网易有道翻译（默认开启且优先展示）**：参考 `Easydict` 接入有道 Web 翻译接口，免 API Key 开箱即用，中英日韩多语种直译准确。
2. **苹果自带翻译（Apple Translate）**：基于 macOS `Translation.framework` 离线翻译（需 macOS 26+ 并在「系统设置 → 通用 → 语言与地区 → 翻译语言」下载对应语种离线包）。
3. **OpenAI 通用协议大模型**：支持配置任意兼容 `/v1/chat/completions` 的 `Base URL`、加密 `API Key`（保存在 Lucent `.vault`）、模型名称与自定义提示词。
4. **Google Gemini 通用协议大模型**：支持配置 `Base URL`（默认 `https://generativelanguage.googleapis.com`）、加密 `API Key`、模型名称（默认 `gemini-3.5-flash-lite`）与自定义提示词。
5. **本地 Ollama 大模型 & 内置公共通道**：支持并行输出多引擎译文对比，并可自由配置首选引擎及是否展示词典释义、原文引用、操作按钮与错误提示。

## 日常使用方式

1. **鼠标划词即出翻译按钮**：在通用设置开启「鼠标划词悬浮按钮」并授予 macOS「辅助功能」权限后，在支持 Accessibility 选区的应用中拖选或双击单词，光标上方会自动弹出操作条。
2. **快捷键直达**：在插件设置页为「划词即译（`selection-translate`）」绑定全局热键，任意应用选中文字后按快捷键即可翻译（支持 `⌘C` 自动兜底）。
3. **快捷台与截图识字联动**：按 `⌥Space` 输入 `tr <文本>` 或 `>ja <文本>` 随时互译；或 `⌥O` 截图识字后点击「发送到流光译站」。
