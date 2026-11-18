import AppKit
import LucentCore
import SwiftUI

final class RoundedGlassContainerView: NSVisualEffectView {
    private var currentCornerRadius: CGFloat
    private let outerRimLayer = CAGradientLayer()
    private let outerRimMask = CALayer()
    private let innerRimLayer = CAGradientLayer()
    private let innerRimMask = CALayer()

    init(cornerRadius: CGFloat = LiquidRadii.panel) {
        self.currentCornerRadius = cornerRadius
        super.init(frame: .zero)
        blendingMode = .behindWindow; state = .active
        isEmphasized = true; wantsLayer = true
        configureSpecularRimLayers()
        applyCurrentThemeMetrics(force: true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChanged), name: .lucentThemeDidChange, object: nil
        )
    }

    @objc private func handleThemeChanged() {
        applyCurrentThemeMetrics(force: false)
    }

    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layoutRimLayers()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRimAppearance()
    }

    func applyCurrentThemeMetrics(force: Bool) {
        let isPrism = ThemeManager.currentSnapshot == .prismPulse
        material = isPrism ? .popover : .menu
        updateCornerRadius(LiquidRadii.panel, force: force)
        updateRimAppearance()
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

    private func configureSpecularRimLayers() {
        for (gradient, mask) in [(outerRimLayer, outerRimMask), (innerRimLayer, innerRimMask)] {
            gradient.isGeometryFlipped = true
            gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
            gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
            gradient.zPosition = 999
            mask.backgroundColor = nil; mask.cornerCurve = .continuous; mask.borderColor = NSColor.black.cgColor
            gradient.mask = mask
            layer?.addSublayer(gradient)
        }
        outerRimMask.borderWidth = 1.1
        innerRimMask.borderWidth = 0.75
    }

    private func layoutRimLayers() {
        outerRimLayer.frame = bounds; outerRimMask.frame = bounds; outerRimMask.cornerRadius = currentCornerRadius
        let insetBounds = bounds.insetBy(dx: 1.2, dy: 1.2)
        innerRimLayer.frame = insetBounds
        innerRimMask.frame = CGRect(origin: .zero, size: insetBounds.size)
        innerRimMask.cornerRadius = max(0, currentCornerRadius - 1.2)
    }

    private func updateRimAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isPrism = ThemeManager.currentSnapshot == .prismPulse
        if SystemDisplayPreferences.shared.increaseContrast || !isPrism {
            let alpha: CGFloat = SystemDisplayPreferences.shared.increaseContrast ? 0.28 : (isDark ? 0.18 : 0.12)
            let edge = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).cgColor
            outerRimLayer.colors = [edge, edge]; outerRimLayer.locations = [0.0, 1.0]
            innerRimLayer.isHidden = true
            return
        }
        innerRimLayer.isHidden = false
        outerRimLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.50 : 0.80).cgColor,
            NSColor.systemCyan.withAlphaComponent(isDark ? 0.18 : 0.22).cgColor,
            NSColor.systemPink.withAlphaComponent(isDark ? 0.30 : 0.34).cgColor
        ]
        outerRimLayer.locations = [0.0, 0.48, 1.0]
        innerRimLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.24 : 0.40).cgColor,
            NSColor.systemPurple.withAlphaComponent(isDark ? 0.18 : 0.14).cgColor,
            NSColor.clear.cgColor
        ]
        innerRimLayer.locations = [0.0, 0.5, 1.0]
    }

    private static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let safeRadius = max(2, cornerRadius)
        let inset = ceil(safeRadius * 1.6) + 1
        let edge = inset * 2 + 4
        let renderer = ImageRenderer(content: RoundedRectangle(cornerRadius: safeRadius, style: .continuous).fill(Color.black).frame(width: edge, height: edge))
        renderer.scale = 2.0
        let image: NSImage
        if let rendered = renderer.nsImage {
            rendered.size = NSSize(width: edge, height: edge); image = rendered
        } else {
            image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
                NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: safeRadius, yRadius: safeRadius).fill(); return true
            }
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }
}
