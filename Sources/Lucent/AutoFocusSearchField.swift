import AppKit
import LucentCore
import SwiftUI

enum OverlayKeyAction: Sendable {
    case moveUp
    case moveDown
    case submit
    case pasteSubmit
    case plainTextSubmit
    case escape
    case cycleMode
    case deleteBackwardWhenEmpty
    case togglePreview
    case toggleActionMenu
    case revealInFinder
    case openSettings
}

private final class CrispSearchTextField: NSTextField {
    override var allowsVibrancy: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshThemeTypography(placeholder: placeholderAttributedString?.string)
    }

    func refreshThemeTypography(placeholder: String?) {
        textColor = LiquidColors.primaryNSColor
        if let editor = currentEditor() as? NSTextView {
            editor.textColor = LiquidColors.primaryNSColor
            editor.insertionPointColor = LiquidColors.primaryNSColor
        }
        if let placeholder {
            placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: LiquidColors.placeholderNSColor,
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium)
                ]
            )
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let panel = window as? KeyableFloatingPanel else { return }
        panel.searchField = self
        DispatchQueue.main.async { [weak panel, weak self] in
            guard let panel, let self, self.window === panel, panel.isVisible else { return }
            panel.focusSearchFieldIfNeeded(moveCursorToEnd: true)
        }
    }
}

struct AutoFocusSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onAction: (OverlayKeyAction) -> Void
    var onQuickSelectIndex: ((Int) -> Void)? = nil
    var onCopyCandidate: (() -> Void)? = nil
    var onSecondarySubmit: (() -> Void)? = nil
    var onDeleteCandidate: (() -> Bool)? = nil
    var onUndoCandidateDelete: (() -> Bool)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = CrispSearchTextField(string: text)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true; field.cell?.wraps = false; field.cell?.isScrollable = true
        field.delegate = context.coordinator
        let localized = L10n.translate(placeholder)
        field.refreshThemeTypography(placeholder: localized)
        context.coordinator.lastPlaceholder = localized
        context.coordinator.lastThemeSignature = Self.currentThemeSignature()
        context.coordinator.installMonitor(for: field)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        let activeEditor = nsView.currentEditor() as? NSTextView
        if activeEditor?.hasMarkedText() != true, nsView.stringValue != text {
            nsView.stringValue = text
        }
        let localizedPlaceholder = L10n.translate(placeholder)
        let themeSignature = Self.currentThemeSignature()
        if context.coordinator.lastPlaceholder != localizedPlaceholder || context.coordinator.lastThemeSignature != themeSignature {
            if let crisp = nsView as? CrispSearchTextField {
                crisp.refreshThemeTypography(placeholder: localizedPlaceholder)
            } else {
                nsView.textColor = LiquidColors.primaryNSColor
                nsView.placeholderAttributedString = NSAttributedString(
                    string: localizedPlaceholder,
                    attributes: [.foregroundColor: LiquidColors.placeholderNSColor, .font: NSFont.systemFont(ofSize: 16, weight: .medium)]
                )
            }
            context.coordinator.lastPlaceholder = localizedPlaceholder
            context.coordinator.lastThemeSignature = themeSignature
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.scheduleFocus(for: nsView, token: focusToken)
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    private static func currentThemeSignature() -> String {
        "\(ThemeManager.currentSnapshot.rawValue):\(ThemeManager.resolvedIsDarkSnapshot)"
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusSearchField
        var lastFocusToken: Int = -1
        var lastPlaceholder: String = ""
        var lastThemeSignature: String = ""
        private var keyMonitor: Any?

        init(parent: AutoFocusSearchField) {
            self.parent = parent
        }

        func scheduleFocus(for field: NSTextField, token: Int) {
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, let window = field.window, window.isVisible else { return }
                self.lastFocusToken = token
                let activeEditor = field.currentEditor() as? NSTextView
                if activeEditor == nil || window.firstResponder !== activeEditor {
                    _ = window.makeFirstResponder(field)
                }
                if let editor = window.fieldEditor(false, for: field) as? NSTextView, !editor.hasMarkedText() {
                    let len = (field.stringValue as NSString).length
                    editor.setSelectedRange(NSRange(location: len, length: 0))
                }
            }
        }

        func installMonitor(for field: NSTextField) {
            removeMonitor()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self, weak field] event in
                guard let self, let field, let win = field.window, win.isKeyWindow, event.window === win else {
                    return event
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.type == .leftMouseDown, flags.contains(.command) {
                    win.performDrag(with: event)
                    return nil
                }
                if event.type == .keyDown {
                    if field.currentEditor() == nil, !(win.firstResponder is NSTextView) {
                        _ = win.makeFirstResponder(field)
                        if let editor = win.fieldEditor(false, for: field) as? NSTextView, !editor.hasMarkedText() {
                            let len = (field.stringValue as NSString).length
                            editor.setSelectedRange(NSRange(location: len, length: 0))
                        }
                    }
                    return self.handleCommandKeyDown(event: event, flags: flags, field: field, window: win)
                }
                return event
            }
        }

        private func handleCommandKeyDown(
            event: NSEvent,
            flags: NSEvent.ModifierFlags,
            field: NSTextField,
            window: NSWindow
        ) -> NSEvent? {
            let editor = window.fieldEditor(false, for: field) as? NSTextView
            if editor?.hasMarkedText() == true {
                return event
            }
            let cleanFlags = flags.subtracting([.numericPad, .function])
            if cleanFlags == .shift && (event.keyCode == 36 || event.keyCode == 76) {
                parent.onAction(.pasteSubmit)
                return nil
            }
            if cleanFlags == .option && (event.keyCode == 36 || event.keyCode == 76) {
                parent.onAction(.plainTextSubmit)
                return nil
            }
            if cleanFlags == .command && (event.keyCode == 36 || event.keyCode == 76) {
                if let onSecondarySubmit = parent.onSecondarySubmit {
                    onSecondarySubmit()
                    return nil
                }
                return event
            }
            if cleanFlags == .command && event.keyCode == 51 {
                if parent.onDeleteCandidate?() == true {
                    return nil
                }
                return event
            }
            guard let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            if flags == [.command, .shift], key == "c", let onCopyCandidate = parent.onCopyCandidate {
                onCopyCandidate()
                return nil
            }
            if cleanFlags == .command, key.count == 1, let digit = Int(key), (1...9).contains(digit) {
                if let onQuickSelectIndex = parent.onQuickSelectIndex {
                    onQuickSelectIndex(digit - 1)
                    return nil
                }
                return event
            }
            guard cleanFlags == .command else { return event }
            switch key {
            case "v":
                if let activeEditor = window.fieldEditor(true, for: field) as? NSTextView { activeEditor.paste(nil); return nil }
            case "a":
                if let activeEditor = window.fieldEditor(true, for: field) as? NSTextView { activeEditor.selectAll(nil); return nil }
            case "x":
                if let activeEditor = window.fieldEditor(true, for: field) as? NSTextView { activeEditor.cut(nil); return nil }
            case "c":
                let hasSelection = (editor?.selectedRange().length ?? 0) > 0
                if !hasSelection, let onCopyCandidate = parent.onCopyCandidate { onCopyCandidate(); return nil }
            case "z":
                let canTextUndo = !field.stringValue.isEmpty && (editor?.undoManager?.canUndo == true)
                if !canTextUndo, parent.onUndoCandidateDelete?() == true { return nil }
            case "y": parent.onAction(.togglePreview); return nil
            case "k": parent.onAction(.toggleActionMenu); return nil
            case "r": parent.onAction(.revealInFinder); return nil
            case ",": parent.onAction(.openSettings); return nil
            default: break
            }
            return event
        }

        func removeMonitor() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)): parent.onAction(.moveUp); return true
            case #selector(NSResponder.moveDown(_:)): parent.onAction(.moveDown); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onAction(.submit); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onAction(.escape); return true
            case #selector(NSResponder.insertTab(_:)): parent.onAction(.cycleMode); return true
            case #selector(NSResponder.deleteBackward(_:)):
                guard textView.string.isEmpty else { return false }
                parent.onAction(.deleteBackwardWhenEmpty); return true
            default: return false
            }
        }
    }
}
