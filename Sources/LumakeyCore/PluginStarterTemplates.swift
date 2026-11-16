import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginStarterGallery {
    /// 官方内置精选模板：仅保留与宿主内置工具（`DevToolkitEngine` / `SystemPulse` / `LumaLink`）完全正交、零功能重叠的三款完整实用扩展。
    public static let templates: [PluginStarterTemplate] = [
        netDiagStarterTemplate,
        portManagerStarterTemplate,
        inboxNoteStarterTemplate
    ]
}
