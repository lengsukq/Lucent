import Foundation
import LucentCore
import WebKit

@MainActor
extension PluginWebBridgeCoordinator {
    func handleSessionStart(
        body: [String: Any],
        plugin: PluginDescriptor,
        vm: AppViewModel
    ) -> [String: Any] {
        if let existing = sessionProcess, existing.isRunning {
            return ["ok": true, "running": true, "alreadyRunning": true]
        }
        stopWindowSession()
        let args = (body["args"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? ["--session"]
        let bridgeCtx = vm.makePluginBridgeContext()
        do {
            let proc = try PluginWindowSessionProcess(
                descriptor: plugin,
                arguments: args,
                hostContext: bridgeCtx,
                onEventLine: { [weak self] lineData in
                    Task { @MainActor [weak self] in
                        self?.forwardSessionEventLine(lineData)
                    }
                },
                onExit: { [weak self] status, stderrText in
                    Task { @MainActor [weak self] in
                        self?.handleSessionExited(status: status, stderrText: stderrText)
                    }
                }
            )
            sessionProcess = proc
            return ["ok": true, "running": true]
        } catch {
            return ["ok": false, "running": false, "error": error.localizedDescription]
        }
    }

    func handleSessionSend(body: [String: Any]) -> [String: Any] {
        guard let proc = sessionProcess, proc.isRunning else {
            return ["ok": false, "error": "session_not_running", "message": "会话进程未运行"]
        }
        guard let message = body["message"] else {
            return ["ok": false, "error": "invalid_params", "message": "缺少 message 参数"]
        }
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message) else {
            return ["ok": false, "error": "invalid_json", "message": "message 必须是合法 JSON 对象或数组"]
        }
        let sent = proc.sendLineData(data)
        return sent
            ? ["ok": true]
            : ["ok": false, "error": "write_failed", "message": "写入会话管道失败或消息超出大小限制"]
    }

    func handleSessionStop() -> [String: Any] {
        stopWindowSession()
        return ["ok": true, "running": false]
    }

    func stopWindowSession() {
        let proc = sessionProcess
        sessionProcess = nil
        proc?.stop(waitGraceSeconds: 0.12)
    }

    private func forwardSessionEventLine(_ lineData: Data) {
        guard let webView = boundWebView,
              let obj = try? JSONSerialization.jsonObject(with: lineData),
              JSONSerialization.isValidJSONObject(obj),
              let safeData = try? JSONSerialization.data(withJSONObject: obj),
              let safeJSON = String(data: safeData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__lucentDispatchWindowEvent && window.__lucentDispatchWindowEvent(\"lucent:sessionEvent\", \(safeJSON));")
    }

    private func handleSessionExited(status: Int32, stderrText: String) {
        sessionProcess = nil
        guard let webView = boundWebView else { return }
        let detail: [String: Any] = ["exitCode": Int(status), "stderr": stderrText]
        guard let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__lucentDispatchWindowEvent && window.__lucentDispatchWindowEvent(\"lucent:sessionExit\", \(json));")
    }
}
