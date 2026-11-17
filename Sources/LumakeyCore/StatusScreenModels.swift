import LumakeyFoundation
import AppKit
import Foundation

public struct StatusScreenConfiguration: Sendable, Equatable {
    public let preset: String
    public let icon: String
    public let title: String
    public let subtitle: String
    public let blockInput: Bool
    public let keepAwake: Bool
    public let muteAudio: Bool
    public let holdSeconds: Double

    public init(
        preset: String = "clean",
        icon: String = "🧹",
        title: String = "",
        subtitle: String = "",
        blockInput: Bool = true,
        keepAwake: Bool = true,
        muteAudio: Bool = false,
        holdSeconds: Double = 2.0
    ) {
        let normalizedPreset = preset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.preset = normalizedPreset.isEmpty ? "custom" : normalizedPreset
        let defaults = Self.defaultStrings(for: self.preset)
        let cleanIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSub = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.icon = cleanIcon.isEmpty ? defaults.icon : String(cleanIcon.prefix(8))
        self.title = cleanTitle.isEmpty ? defaults.title : String(cleanTitle.prefix(80))
        self.subtitle = cleanSub.isEmpty ? defaults.subtitle : String(cleanSub.prefix(140))
        self.blockInput = blockInput
        self.keepAwake = keepAwake
        self.muteAudio = muteAudio
        self.holdSeconds = min(max(holdSeconds, 1.0), 5.0)
    }

    public static func defaultHintText(holdSeconds: Double) -> String {
        let s = String(format: "%.0f", holdSeconds)
        return L10n.pick("按住 Esc \(s) 秒退出状态屏", "Hold Esc for \(s)s to exit status screen")
    }

    private static func defaultStrings(for preset: String) -> (icon: String, title: String, subtitle: String) {
        switch preset {
        case "clean":
            return ("🧹", L10n.pick("正在清洁屏幕与键盘", "Cleaning Screen & Keyboard"),
                    L10n.pick("键鼠误触已临时拦截，可放心擦拭", "Keyboard & mouse touches are temporarily blocked"))
        case "busy":
            return ("⚡", L10n.pick("任务运行中 · 请勿触碰", "Task Running · Do Not Touch"),
                    L10n.pick("后台任务正在执行，屏幕与防休眠保护已开启", "Background task in progress with sleep guard active"))
        case "brb":
            return ("☕", L10n.pick("马上回来", "Be Right Back"),
                    L10n.pick("暂时离开座位，稍后即回", "Stepped away briefly — back in a moment"))
        default:
            return ("🛡️", L10n.pick("状态屏保护中", "Status Screen Active"),
                    L10n.pick("当前处于全屏告示状态", "Fullscreen status notice is active"))
        }
    }
}

final class StatusScreenShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum StatusScreenShieldViewBuilder {
    @MainActor
    static func build(
        size: NSSize,
        config: StatusScreenConfiguration,
        target: AnyObject,
        emergencyAction: Selector
    ) -> (NSView, NSTextField) {
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0).cgColor

        let iconField = NSTextField(labelWithString: config.icon)
        iconField.font = .systemFont(ofSize: 68)
        iconField.alignment = .center

        let titleField = NSTextField(labelWithString: config.title)
        titleField.font = .systemFont(ofSize: 32, weight: .bold)
        titleField.textColor = .white
        titleField.alignment = .center

        let subField = NSTextField(labelWithString: config.subtitle)
        subField.font = .systemFont(ofSize: 16, weight: .regular)
        subField.textColor = NSColor.white.withAlphaComponent(0.68)
        subField.alignment = .center

        let hintField = NSTextField(labelWithString: StatusScreenConfiguration.defaultHintText(holdSeconds: config.holdSeconds))
        hintField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        hintField.textColor = NSColor.white.withAlphaComponent(0.52)
        hintField.alignment = .center

        let unlockBtn = NSButton(
            title: L10n.pick("双击此处也可立即退出", "Double-click here to exit"),
            target: target,
            action: emergencyAction
        )
        unlockBtn.bezelStyle = .recessed
        unlockBtn.isBordered = true
        unlockBtn.alphaValue = 0.45

        let centerStack = NSStackView(views: [iconField, titleField, subField])
        centerStack.orientation = .vertical
        centerStack.spacing = 14
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        let bottomStack = NSStackView(views: [hintField, unlockBtn])
        bottomStack.orientation = .vertical
        bottomStack.spacing = 8
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(centerStack)
        root.addSubview(bottomStack)
        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -20),
            bottomStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -48)
        ])
        return (root, hintField)
    }
}
