import PluginKit

let input = PluginInput.read()
let title = input.isEnglish ? "File Shelf" : "文件中转站"
let hasFiles = !(input.context?.filePaths.isEmpty ?? true)
if input.arguments.contains("--sync") {
    PluginOutput.emit(ViewPayload(title: title))
} else {
    let response = HostBridgeClient(input: input).call(
        capability: "fileShelf",
        action: hasFiles ? "addContextItems" : "open"
    )
    if response.ok {
        PluginOutput.emit(ViewPayload(title: title, effect: PostActionEffect(closeOverlay: true)))
    } else {
        let detail = input.isEnglish
            ? "Open this demo in Lucent and grant File Shelf access."
            : "请在 Lucent 中打开，并允许使用文件中转站。"
        PluginOutput.emit(ViewPayload(title: title, subtitle: detail))
    }
}
