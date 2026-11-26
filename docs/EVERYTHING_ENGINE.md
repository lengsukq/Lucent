# Everything 检索引擎设计

为在 macOS 上获得类似 Windows Everything 的即时筛选手感，`Lucent` 采用**多根目录内存紧凑父指针树 (`EverythingIndex`) + 查询 DSL 解析器 (`EverythingQuery`)**。

## 内存结构设计

传统文件树为每个节点保存完整绝对路径会成倍放大堆内存与字符串分配开销。`LucentSearch` 采用平坦数组存储，并通过 `rootIndex` 默认同时索引本机主目录与全部已挂载外置磁盘（`EverythingScope.allVolumes`，亦可一键切换至常用目录或单一卷）：

```swift
public struct IndexedNode: Sendable, Hashable {
    public let parentID: Int32 // 根节点直接子项为 -1
    public let rootIndex: UInt16
    public let isDirectory: Bool
    public let name: String
}
```

- **Darwin `getattrlistbulk` 批量目录扫描 + POSIX 降级 + 零冗余分配匹配**：`DirectoryEntryEnumerator` 优先调用 `getattrlistbulk` 单次系统调用批量拉取目录项名称与 `ATTR_CMN_OBJTYPE`（复用 32 KB 缓冲区、免去外置盘与深层目录大量逐项 `stat` RPC，在不支持批量属性的 FUSE/NTFS/SMB 卷上自动无缝降级为 `opendir`/`readdir`），采用 `24 B` 紧凑 `IndexedNode`（去除全量小写/扩展名副本与无效字段），查询期由 `QueryNeedle` 对 `name` 执行原地 UTF-8 大小写折叠匹配并在 Top N 命中时按需 `stat` 补齐文件大小、修改时间与卷前缀路径。
- **确定性有界遍历与工程构建产物上下文跳过**：默认跳过 `Library`、`node_modules`、`.git`、`.build`、`DerivedData`、`Caches`、`.Spotlight-V100`、`.Trashes`、`$RECYCLE.BIN`、`.venv`、`.next`/`.turbo`/`.dart_tool` 等缓存目录，并在同级存在对应工程清单（如 `Cargo.toml` 旁的 `target`、`pubspec.yaml`/`build.gradle`/`Package.swift`/`CMakeLists.txt` 旁的 `build` 及 `go/pkg/mod`）时自动跳过构建输出目录，避免构建产物挤占节点配额且不误伤普通用户文件夹；设置节点上限并在 `Task.isCancelled` 时协作退出。

## 查询 DSL 语法

`EverythingQuery` 将用户输入的查询串解析为**若干 OR (`|`) 子句，每个子句包含若干 AND 词项**：

| 语法词项 | 含义与示例 |
| --- | --- |
| 普通关键词 | 大小写不敏感文件名匹配，如 `report 2026` |
| `ext:a;b;c` | 扩展名集合匹配，如 `ext:swift;md` 或 `ext:mp4;mkv` |
| `folder:` | 仅匹配文件夹 |
| `file:` | 仅匹配普通文件 |
| `video:` | 视频扩展名预设 (`mp4/mov/m4v/mkv/avi/webm/ts/flv`) |
| `pic:` | 图片扩展名预设 (`png/jpg/jpeg/webp/heic/gif/tiff/bmp/raw/dng`) |
| `path:substr` | 父目录路径子串匹配（触发时按需解析父路径） |
| `!term` | 逻辑取反排除条件，可与上述任意词项组合，如 `!ext:tmp !.git` |
| `A \| B` | 多组条件“或”连接，如 `ext:png \| ext:jpg` |

## 持久化二进制快照与 FSEvents 增量同步

- **紧凑二进制快照、SHA-256 校验与 O(1) 头部启动 (`EverythingSnapshotStore`)**：将 `IndexedNode` 父指针树以 `LCNTIDX4` 紧凑格式落盘至 `~/Library/Caches/app.lucent.macos/everything-index/idx-<sha256>.lcntidx`（每节点仅 `9 B + UTF-8`，头部记录 `lastEventId`、尾部追加 32 字节 `SHA-256` 完整性摘要）。冷启动仅通过 `readHeaderMetadata(...)` 读取前 4 KB 校验根目录、获取节点总数与上次 `lastEventId`（实现启动期零内存索引驻留）；切入文件模式或输入搜索词时通过 `Data(contentsOf:options: .mappedIfSafe)` 恢复内存检索，先校验尾部 `SHA-256` 摘要与 BFS 父节点拓扑无环边界，再结合 `mtime`/`ctime` 对账离线改动并安全写回，遇到断电截断或位翻转损坏自动返回 `nil` 触发安全重扫，闲置 `90s` 无损转存脏目录后卸载内存。
- **macOS `FSEvents` 实时增量更新 (`EverythingFSEventWatcher` + `applyingFSEventDirectories`)**：针对本机与快速外置卷监听 `FSEventStreamCreate` 事件（`80ms` 流延迟、`0.2s` 防抖 + `0.55s` 最大等待上限防饥饿），直接前置过滤 `Library`/隐藏文件/构建缓存与非结构性纯内容修改以杜绝自激循环与噪音干扰；目录重命名自动升级为子树扫描、缺失祖先目录自动向上补全，并配合唤起时 `FSEventStreamFlushAsync`、休眠唤醒对账与工作台本地文件操作 0ms 直通同步，其余未变分支零系统调用复用原节点。

## 在快捷台与独立模式中的集成

- **独立秒搜模式 (`⌥F`)**：打开后直接展示作用域与语法胶囊，并自动在右侧开启 `300pt` 侧边玻璃预览镜。
- **快捷台内联直达 (`⌥Space`)**：输入 `f `、`open `、`find ` 或任意 `ext:`/`pic:`/`video:`/`folder:`/`path:` DSL 时，可在主快捷台直接检索并打开命中文件。
- **工作台目录缓存与相关性排序协同**：查询引擎按精确命中、词干命中、前缀命中、子串命中与文件名长度进行相关性择优排序（双桶有界收集 `highCap = max(limit * 8, 512)` 与 `lowCap = max(limit * 4, 192)` 候选，避免高相关文件被扫描顺序淹没）；文件工作台 (`⌥E`) 采用 `WorkspaceDirectoryCache` 48 项 LRU + SWR 异步刷新与 `IconCache` 扩展名图标复用。
