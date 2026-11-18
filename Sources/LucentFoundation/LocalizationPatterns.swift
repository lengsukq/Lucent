import Foundation

enum LocalizationPatterns {
    private static let prefixMap: [(zh: String, en: String)] = [
        ("插件设置 · ", "Plugin Settings · "),
        ("前置：", "Bring to Front: "),
        ("文档阅读 · ", "Reader · "),
        ("只读看图 · ", "Image Viewer · "),
        ("影院播片 · ", "Cinema Player · "),
        ("已粘贴：", "Pasted: "),
        ("已复制：", "Copied: "),
        ("已打开：", "Opened: "),
        ("已复制路径：", "Copied path: "),
        ("已复制应用路径：", "Copied app path: "),
        ("已复制剪贴板项：", "Copied clipboard item: "),
        ("已复制展开短语：", "Copied snippet: "),
        ("已展开并复制短语：", "Expanded & copied snippet: "),
        ("已展开并复制：", "Expanded & copied: "),
        ("已复制子功能名称：", "Copied command: "),
        ("已复制结果：", "Copied result: "),
        ("已复制计算结果：", "Copied calculation: "),
        ("已复制 HEX：", "Copied HEX: "),
        ("已复制色值 ", "Copied color "),
        ("已在浏览器打开 ", "Opened in browser: "),
        ("已保存短语：", "Saved snippet: "),
        ("已删除短语：", "Deleted snippet: "),
        ("已创建插件：", "Created plugin: "),
        ("已导入插件：", "Imported plugin: "),
        ("已移除插件：", "Removed plugin: "),
        ("已安装精选模板：", "Installed template: "),
        ("已上传云备份：", "Uploaded cloud backup: "),
        ("云备份失败：", "Cloud backup failed: "),
        ("已删除云端快照：", "Deleted remote backup: "),
        ("恢复前快照核验：", "Snapshot Check: "),
        ("云端 · ", "Cloud · "),
        ("位置：", "Location: "),
        ("原名称：", "Original: "),
        ("启动失败：", "Failed to start: "),
        ("监听异常：", "Listener error: "),
        ("已绑定全局热键：", "Bound global hotkey: "),
        ("已更新触发词：", "Updated keywords: "),
        ("已恢复默认触发词：", "Restored default keywords: "),
        ("默认触发词：", "Default keywords: "),
        ("触发词: ", "Keywords: "),
        ("条码: ", "Barcodes: "),
        ("热态：", "Thermal: "),
        ("实时运行测试 · ", "Live Test · "),
        ("正在运行插件：", "Running plugin: "),
        ("插件：", "Plugin: "),
        ("配对时间：", "Paired: "),
        ("已导出至 ", "Exported to "),
        ("GIF 已另存为：", "GIF saved as: "),
        ("截图已保存并复制到剪贴板：", "Screenshot saved & copied: "),
        ("内部重复：", "Internal duplicate: "),
        ("插件冲突：", "Plugin conflict: "),
        ("系统保留键：", "System reserved: "),
        ("打开磁盘 ", "Open Volume ")
    ]

    private static let suffixMap: [(zh: String, en: String)] = [
        (" 节点", " nodes"),
        (" 索引项", " index items"),
        (" 文件", " files"),
        (" 字符", " chars"),
        (" 条", " items"),
        (" 项", " items"),
        (" 个", ""),
        (" 帧", " frames"),
        ("帧", " frames"),
        (" 权限", " perms"),
        ("% 透明", "% opacity"),
        ("个数据文件", "data files"),
        (" 项配置文件", " config files"),
        (" 条收藏剪贴板", " pinned clips"),
        (" 个外部插件", " external plugins")
    ]

    static func translateDynamic(_ text: String, table: [String: String]) -> String {
        for (zhPre, enPre) in prefixMap where text.hasPrefix(zhPre) {
            let rest = String(text.dropFirst(zhPre.count))
            let translatedRest = table[rest] ?? rest
            return enPre + translatedRest
        }
        for (zhSuf, enSuf) in suffixMap where text.hasSuffix(zhSuf) {
            let head = String(text.dropLast(zhSuf.count))
            if head.allSatisfy({ $0.isNumber || $0 == "/" || $0 == "." || $0 == " " || $0 == "+" || $0 == "-" }) {
                return enSuf.isEmpty ? head : (head + enSuf)
            }
        }
        if text.hasPrefix("在「"), let closeIdx = text.range(of: "」中筛选词条或输入参数按 ↩ 执行...") {
            let name = String(text[text.index(text.startIndex, offsetBy: 2)..<closeIdx.lowerBound])
            return "Filter items or pass arguments to \"\(name)\" (↩ to run)..."
        }
        if text.hasPrefix("带着当前输入实时执行「"), text.hasSuffix("」") {
            let name = String(text.dropFirst("带着当前输入实时执行「".count).dropLast())
            return "Run \"\(name)\" live with current input"
        }
        if text.hasPrefix("已切换至「"), text.hasSuffix("主题") {
            return "Switched theme: " + text
                .replacingOccurrences(of: "已切换至「", with: "")
                .replacingOccurrences(of: "」", with: " ")
                .replacingOccurrences(of: " 主题", with: "")
        }
        if text.hasPrefix("ID: "), text.contains(" · 触发词: ") {
            return text.replacingOccurrences(of: " · 触发词: ", with: " · Keywords: ")
        }
        if text.hasPrefix("全部已启用 ("), text.hasSuffix(")") {
            return text.replacingOccurrences(of: "全部已启用 (", with: "All Enabled (")
        }
        if text.hasPrefix("播放列表 ("), text.hasSuffix(")") {
            return text.replacingOccurrences(of: "播放列表 (", with: "Playlist (")
        }
        if text.hasPrefix("同目录视频 ("), text.hasSuffix(")") {
            return text.replacingOccurrences(of: "同目录视频 (", with: "Folder Videos (")
        }
        if text.hasPrefix("外部扩展插件 ("), text.hasSuffix(")") {
            return text.replacingOccurrences(of: "外部扩展插件 (", with: "External Plugins (")
        }
        if text.hasPrefix("全部关闭快捷按钮 ("), text.hasSuffix(")") {
            return text.replacingOccurrences(of: "全部关闭快捷按钮 (", with: "Disable All Quick Buttons (")
        }
        if text.hasPrefix("共 "), text.hasSuffix(" 项子功能") {
            let n = text.dropFirst(2).dropLast(" 项子功能".count)
            return "\(n) Sub-Commands"
        }
        if text.hasPrefix("已调用 "), text.contains(" 次 · 综合加权 ") {
            return text
                .replacingOccurrences(of: "已调用 ", with: "Invoked ")
                .replacingOccurrences(of: " 次 · 综合加权 ", with: "× · Score Boost ")
        }
        if text.hasPrefix("保留最近 "), text.hasSuffix(" 份") {
            let n = text.dropFirst("保留最近 ".count).dropLast(2)
            return "Keep latest \(n)"
        }
        return text
    }
}
