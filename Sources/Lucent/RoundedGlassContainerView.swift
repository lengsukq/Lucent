import AppKit
import LucentCore
import SwiftUI

final class RoundedGlassContainerView: NSVisualEffectView {
    private var currentCornerRadius: CGFloat
    private let outerRimLayer = CAGradientLayer()
    private let outerRimMask = CALayer()
    private let innerRimLayer = CAGradientLayer()
    private let innerRimMask = CALayer()
    private let sheenSweepLayer = CAGradientLayer()
    private let sheenSweepMask = CALayer()
    private weak var observedWindow: NSWindow?

    init(cornerRadius: CGFloat = LiquidRadii.panel) {
        self.currentCornerRadius = cornerRadius
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
        wantsLayer = true
        configureSpecularRimLayers()
        applyCurrentThemeMetrics(force: true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChanged), name: .lucentThemeDidChange, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleThemeChanged() {
        applyCurrentThemeMetrics(force: false)
        triggerSpecularSheenSweep()
    }

    @objc private func handleWindowDidBecomeKey() {
        triggerSpecularSheenSweep()
    }

    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let prev = observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: prev)
            observedWindow = nil
        }
        if let win = window {
            observedWindow = win
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleWindowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: win
            )
            triggerSpecularSheenSweep()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutRimLayers()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCurrentThemeMetrics(force: false)
    }

    func applyCurrentThemeMetrics(force: Bool) {
        let isDark = resolvedDarkAppearance()
        material = isDark ? .hudWindow : .popover
        updateCornerRadius(currentCornerRadius, force: force)
        updateRimAppearance(isDark: isDark)
    }

    func updateCornerRadius(_ radius: CGFloat, force: Bool = false) {
        guard force || abs(radius - currentCornerRadius) > 0.4 else { return }
        currentCornerRadius = radius
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        maskImage = Self.makeRoundedMaskImage(cornerRadius: radius)
        layoutRimLayers()
    }

    private func resolvedDarkAppearance() -> Bool {
        if window != nil {
            return effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return ThemeManager.resolvedIsDarkSnapshot
    }

    private func configureSpecularRimLayers() {
        for (gradient, mask) in [(outerRimLayer, outerRimMask), (innerRimLayer, innerRimMask)] {
            gradient.isGeometryFlipped = true
            gradient.startPoint = CGPoint(x: 0.15, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.85, y: 1.0)
            gradient.zPosition = 999
            mask.backgroundColor = nil
            mask.cornerCurve = .continuous
            mask.borderColor = NSColor.black.cgColor
            gradient.mask = mask
            layer?.addSublayer(gradient)
        }
        outerRimMask.borderWidth = 1.1
        innerRimMask.borderWidth = 0.75

        sheenSweepLayer.isGeometryFlipped = true
        sheenSweepLayer.startPoint = CGPoint(x: 0.0, y: 0.12)
        sheenSweepLayer.endPoint = CGPoint(x: 1.0, y: 0.88)
        sheenSweepLayer.zPosition = 998
        sheenSweepLayer.opacity = 0
        sheenSweepMask.backgroundColor = nil
        sheenSweepMask.cornerCurve = .continuous
        sheenSweepMask.borderColor = NSColor.black.cgColor
        sheenSweepMask.borderWidth = 1.35
        sheenSweepLayer.mask = sheenSweepMask
        layer?.addSublayer(sheenSweepLayer)
    }

    private func layoutRimLayers() {
        outerRimLayer.frame = bounds
        outerRimMask.frame = bounds
        outerRimMask.cornerRadius = currentCornerRadius

        let insetBounds = bounds.insetBy(dx: 1.1, dy: 1.1)
        innerRimLayer.frame = insetBounds
        innerRimMask.frame = CGRect(origin: .zero, size: insetBounds.size)
        innerRimMask.cornerRadius = max(0, currentCornerRadius - 1.1)

        sheenSweepLayer.frame = bounds
        sheenSweepMask.frame = bounds
        sheenSweepMask.cornerRadius = currentCornerRadius
    }

    private func updateRimAppearance(isDark: Bool) {
        if SystemDisplayPreferences.shared.increaseContrast {
            let edge = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.32).cgColor
            outerRimLayer.colors = [edge, edge]
            outerRimLayer.locations = [0.0, 1.0]
            innerRimLayer.isHidden = true
            return
        }
        innerRimLayer.isHidden = false
        if isDark {
            outerRimLayer.colors = [
                NSColor.white.withAlphaComponent(0.36).cgColor,
                NSColor(srgbRed: 0.70, green: 0.85, blue: 1.0, alpha: 0.16).cgColor,
                NSColor.white.withAlphaComponent(0.11).cgColor
            ]
            outerRimLayer.locations = [0.0, 0.45, 1.0]
            innerRimLayer.colors = [
                NSColor.white.withAlphaComponent(0.24).cgColor,
                NSColor(srgbRed: 0.78, green: 0.90, blue: 1.0, alpha: 0.08).cgColor,
                NSColor.clear.cgColor
            ]
            innerRimLayer.locations = [0.0, 0.36, 1.0]
        } else {
            outerRimLayer.colors = [
                NSColor.white.withAlphaComponent(0.88).cgColor,
                NSColor.black.withAlphaComponent(0.085).cgColor,
                NSColor.black.withAlphaComponent(0.14).cgColor
            ]
            outerRimLayer.locations = [0.0, 0.42, 1.0]
            innerRimLayer.colors = [
                NSColor.white.withAlphaComponent(0.92).cgColor,
                NSColor.white.withAlphaComponent(0.30).cgColor,
                NSColor.clear.cgColor
            ]
            innerRimLayer.locations = [0.0, 0.34, 1.0]
        }
    }

    private func triggerSpecularSheenSweep() {
        let prefs = SystemDisplayPreferences.shared.snapshot
        guard !prefs.reduceMotion, !prefs.reduceTransparency, !prefs.increaseContrast, bounds.width > 40 else {
            sheenSweepLayer.removeAllAnimations()
            sheenSweepLayer.opacity = 0
            return
        }
        let isDark = resolvedDarkAppearance()
        let glintColor = NSColor.white.withAlphaComponent(isDark ? 0.56 : 0.85).cgColor
        let iceTint = NSColor(srgbRed: 0.64, green: 0.84, blue: 1.0, alpha: isDark ? 0.28 : 0.22).cgColor
        sheenSweepLayer.colors = [NSColor.clear.cgColor, iceTint, glintColor, iceTint, NSColor.clear.cgColor]

        sheenSweepLayer.removeAllAnimations()
        let locAnim = CABasicAnimation(keyPath: "locations")
        locAnim.fromValue = [-0.45, -0.32, -0.20, -0.08, 0.04]
        locAnim.toValue = [0.96, 1.08, 1.20, 1.32, 1.45]
        locAnim.duration = 0.68
        locAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [0.0, 1.0, 0.85, 0.0]
        opacityAnim.keyTimes = [0.0, 0.18, 0.72, 1.0]
        opacityAnim.duration = 0.68

        let group = CAAnimationGroup()
        group.animations = [locAnim, opacityAnim]
        group.duration = 0.68
        group.isRemovedOnCompletion = true
        sheenSweepLayer.add(group, forKey: "lucentSpecularSweep")
    }

    private static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let safeRadius = max(2, cornerRadius)
        let inset = ceil(safeRadius * 1.6) + 1
        let edge = inset * 2 + 4
        let renderer = ImageRenderer(
            content: RoundedRectangle(cornerRadius: safeRadius, style: .continuous)
                .fill(Color.black)
                .frame(width: edge, height: edge)
        )
        renderer.scale = 2.0
        let image: NSImage
        if let rendered = renderer.nsImage {
            rendered.size = NSSize(width: edge, height: edge)
            image = rendered
        } else {
            image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: safeRadius, yRadius: safeRadius).fill()
                return true
            }
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }
}
