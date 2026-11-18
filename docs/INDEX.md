# Lucent 文档总览

所有设计与工程文档采用正交分工，点击下列索引直达对应章节。

- [产品定位与边界](PRODUCT.md)：用户定位、五大核心场景以及明确的“不做清单”。
- [macOS 原生服务复用清单](NATIVE_SERVICES.md)：为什么优先复用系统服务以及每项能力的系统 API 映射。
- [液态玻璃设计规范](DESIGN_SYSTEM.md)：`.ultraThinMaterial`、连续大圆角、光影层级与可访问性降级标准。
- [系统架构与 Clean Code 约束](ARCHITECTURE.md)：目标划分、并发模型、生命周期清理与 300 行文件拆分规范。
- [Everything 检索引擎设计](EVERYTHING_ENGINE.md)：紧凑父指针内存树、查询 DSL 语法及后续系统事件增量演进。
- [插件系统与 MCP 接口规范](PLUGIN_AND_MCP.md)：`plugin.json` v3.7 统一内置/外部模型、独立脚本快捷库 (`Quick Scripts`)、自由画布浮窗 (`WKWebView` HUD)、实时悬浮面板、宿主统一 TCC 代理、强制权限矩阵、Seatbelt 沙箱及 `lucent-mcp` v0.3.3（20 项工具，含快捷脚本库与启动页实时编排）工具说明。
- [版本路线图](ROADMAP.md)：M0 基础验证、M1/M2 原生闭环至 M3 增强能力（`getattrlistbulk`、`ntfs-3g`、外挂字幕）的演进规划。
- [本地开发与构建指南](DEVELOPMENT.md)：环境要求、目录组织、测试与 `.app` 打包流程。
- [当前实现状态](STATUS.md)：如实追踪已完成模块、已验证能力与当前约束。
