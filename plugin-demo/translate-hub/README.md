# 流光译站 · 划词/截图多源翻译与生词本 (`translate-hub`)

Lumakey 官方旗舰翻译与词典插件（Schema v3）：

- **跨应用划词即译 & 剪贴板翻译**：通过 Host Bridge `selection` 读取当前前台选中文本（无选区时自动回退剪贴板），并在第一/第二语言之间自动互译，也支持 `>ja 文本` 临时指定目标语言。
- **截图 / 图片离线 OCR 翻译**：声明 `accepts: ["text", "image"]`，可在图片预览、文件工作台与 `⌥O` Vision 离线识字结果窗一键识别并翻译。
- **开箱即用 + 大模型 / DeepL 多源并行**：默认开启免密钥词典释义与公共翻译通道；在设置页填入 OpenAI 兼容大模型（DeepSeek / OpenRouter / Ollama）或 DeepL 密钥（本机 `LMKYVLT2` `AES-GCM` 保险箱加密）后自动并发输出多源译文对比。
- **原声朗读 & Anki 生词本导出**：支持调用宿主 `audio.speak` 语音朗读，一键收藏生词同步 `⌥Space` 免前缀索引，并可导出可直接导入 Anki 的 `.tsv` 卡片与 UTF-8 `.csv` 表格。
