import AppKit
import Foundation
import LucentCore
import SwiftUI

enum PluginWebSDKBootstrap {
    static let handlerName = "lucentHost"

    @MainActor
    static func buildScript(plugin: PluginDescriptor, spec: PluginCustomWindowSpec) -> String {
        let envDict: [String: Any] = [
            "pluginId": plugin.id,
            "pluginName": plugin.displayName,
            "version": plugin.manifest.version,
            "windowId": spec.windowID,
            "chrome": spec.chrome.rawValue,
            "transparent": spec.transparent,
            "pinOnTop": spec.pinOnTop,
            "opacity": spec.opacity,
            "locale": L10n.current.rawValue,
            "theme": AppThemeConfig.load().selectedTheme.rawValue,
            "networkAllowed": plugin.isResourceScopeGranted(.network),
            "declaredCapabilities": plugin.declaredCapabilities.map(\.rawValue),
            "grantedCapabilities": plugin.grantedCapabilities.map(\.rawValue).sorted(),
            "initialStateJSON": spec.initialStateJSON ?? ""
        ]
        let envJSON = (try? JSONSerialization.data(withJSONObject: envDict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        (function() {
          const env = \(envJSON);
          try { env.initialState = env.initialStateJSON ? JSON.parse(env.initialStateJSON) : null; } catch (_) { env.initialState = env.initialStateJSON; }
          function send(op, payload) {
            return window.webkit.messageHandlers.\(handlerName).postMessage(Object.assign({ op: op }, payload || {}));
          }
          window.__lucentApplyEnvUpdate = function(patch) {
            if (!patch || typeof patch !== "object") return;
            Object.assign(env, patch);
            try {
              window.dispatchEvent(new CustomEvent("lucent:envChanged", { detail: Object.assign({}, env) }));
            } catch (_) {}
          };
          window.__lucentDispatchWindowEvent = function(eventName, detail) {
            if (typeof eventName !== "string" || !eventName) return;
            try {
              window.dispatchEvent(new CustomEvent(eventName, { detail: detail || {} }));
            } catch (_) {}
          };
          function listenWindowEvent(eventName, listener) {
            if (typeof listener !== "function") return () => {};
            const h = (ev) => listener(ev.detail || {});
            window.addEventListener(eventName, h);
            return () => window.removeEventListener(eventName, h);
          }
          function mergeOptions(flagOrOpts, extraOpts, defaultAnimate) {
            if (flagOrOpts && typeof flagOrOpts === "object") {
              return Object.assign({ animate: defaultAnimate }, flagOrOpts);
            }
            const base = { animate: flagOrOpts === undefined ? defaultAnimate : Boolean(flagOrOpts) };
            return extraOpts && typeof extraOpts === "object" ? Object.assign(base, extraOpts) : base;
          }
          window.lucent = Object.freeze({
            env: env,
            onEnvChanged: (listener) => listenWindowEvent("lucent:envChanged", listener),
            run: (args = [], query = "") => send("run", { args: Array.isArray(args) ? args : [], query: String(query || "") }),
            bridge: (capability, action, params = {}) => send("bridge", { capability: String(capability), action: String(action), params: params || {} }),
            permissions: Object.freeze({
              status: () => send("permStatus", {}),
              request: (capability) => send("permRequest", { capability: String(capability) })
            }),
            window: Object.freeze({
              getFrame: () => send("win", { cmd: "getFrame" }),
              startDrag: () => send("win", { cmd: "startDrag" }),
              resize: (width, height, animateOrOpts = true, options = {}) => send("win", Object.assign({ cmd: "resize", width, height }, mergeOptions(animateOrOpts, options, true))),
              moveTo: (x, y, animateOrOpts = false, options = {}) => send("win", Object.assign({ cmd: "moveTo", x, y }, mergeOptions(animateOrOpts, options, false))),
              animateFrame: (options = {}) => send("win", Object.assign({ cmd: "animateFrame" }, options && typeof options === "object" ? options : {})),
              morph: (options = {}) => send("win", Object.assign({ cmd: "morph" }, options && typeof options === "object" ? options : {})),
              snapToEdge: (edge = "nearest", options = {}) => send("win", Object.assign({ cmd: "snapToEdge", edge: String(edge || "nearest") }, options && typeof options === "object" ? options : {})),
              setEdgeBehavior: (options = {}) => send("win", Object.assign({ cmd: "setEdgeBehavior" }, options && typeof options === "object" ? options : {})),
              setPinned: (pinned) => send("win", { cmd: "setPinned", pinned: Boolean(pinned) }),
              setClickThrough: (enabled) => send("win", { cmd: "setClickThrough", enabled: Boolean(enabled) }),
              setOpacity: (opacity, options = {}) => send("win", Object.assign({ cmd: "setOpacity", opacity: Number(opacity) }, options && typeof options === "object" ? options : {})),
              resetFrame: () => send("win", { cmd: "resetFrame" }),
              minimize: () => send("win", { cmd: "minimize" }),
              close: () => send("win", { cmd: "close" }),
              onFrameChanged: (listener) => listenWindowEvent("lucent:frameChanged", listener),
              onDragStart: (listener) => listenWindowEvent("lucent:dragStart", listener),
              onDragMove: (listener) => listenWindowEvent("lucent:dragMove", listener),
              onDragEnd: (listener) => listenWindowEvent("lucent:dragEnd", listener),
              onEdgeProximity: (listener) => listenWindowEvent("lucent:edgeProximity", listener)
            }),
            openExternal: (url) => send("openURL", { url: String(url || "") })
          });
          document.addEventListener("mousedown", function(ev) {
            if (ev.button !== 0) return;
            const dragRegion = ev.target && ev.target.closest ? ev.target.closest("[data-lucent-drag]") : null;
            if (!dragRegion) return;
            if (ev.target.closest("button, a, input, select, textarea, [role='button'], [data-lucent-no-drag]")) return;
            window.lucent.window.startDrag();
          }, true);
        })();
        """
    }
}

struct PluginWindowPermissionGateView: View {
    let plugin: PluginDescriptor
    let capability: PluginCapability
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PluginIconBadge(plugin: plugin, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.pick("「\(plugin.displayName)」请求打开自由窗口", "'\(plugin.displayName)' requests a custom window"))
                        .font(.headline)
                    Text(capability.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
            }
            Text(capability.summary)
                .font(.caption)
                .foregroundStyle(LiquidColors.textSecondary)
            Text(L10n.pick("授权后该插件可自由绘制窗口界面，你随时可在菜单栏或插件设置中关闭权限。", "Once granted, this plugin can render its own custom window UI. You can revoke access anytime in Settings."))
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                Button(L10n.pick("插件设置", "Plugin Settings"), action: onOpenSettings)
                    .buttonStyle(GlassPillButtonStyle())
                Spacer()
                Button(L10n.pick("取消", "Cancel"), action: onCancel)
                    .buttonStyle(GlassPillButtonStyle())
                Button(L10n.pick("允许并打开", "Allow & Open"), action: onAllow)
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}
