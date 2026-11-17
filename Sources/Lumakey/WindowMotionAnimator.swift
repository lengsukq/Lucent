import AppKit
import LumakeyCore
import QuartzCore

enum WindowMotionStyle {
    case launcher
    case launcherFromIntro
    case dynamicIsland
    case floatingPin
    case pulseCapsule
    case standardWindow
    case fullscreenOverlay

    var enterScale: CGFloat {
        switch self {
        case .launcher: 0.958
        case .launcherFromIntro: 0.912
        case .dynamicIsland: 0.91
        case .floatingPin: 0.915
        case .pulseCapsule: 0.925
        case .standardWindow: 0.974
        case .fullscreenOverlay: 1.0
        }
    }

    var exitScale: CGFloat {
        switch self {
        case .launcher, .launcherFromIntro: 0.970
        case .dynamicIsland: 0.92
        case .floatingPin: 0.91
        case .pulseCapsule: 0.935
        case .standardWindow: 0.980
        case .fullscreenOverlay: 1.0
        }
    }

    var enterOffsetY: CGFloat {
        switch self {
        case .launcher: 8
        case .launcherFromIntro: 12
        case .dynamicIsland: 12
        case .floatingPin: -5
        case .pulseCapsule: 6
        case .standardWindow: 10
        case .fullscreenOverlay: 0
        }
    }

    var exitOffsetY: CGFloat {
        switch self {
        case .launcher, .launcherFromIntro: 6
        case .dynamicIsland: 10
        case .floatingPin: 4
        case .pulseCapsule: 5
        case .standardWindow: 6
        case .fullscreenOverlay: 0
        }
    }

    var enterFadeDuration: TimeInterval {
        switch self {
        case .launcher: 0.19
        case .launcherFromIntro: 0.24
        case .dynamicIsland: 0.21
        case .floatingPin: 0.20
        case .pulseCapsule: 0.18
        case .standardWindow: 0.21
        case .fullscreenOverlay: 0.12
        }
    }

    var exitDuration: TimeInterval {
        switch self {
        case .launcher, .launcherFromIntro: 0.135
        case .dynamicIsland: 0.145
        case .floatingPin: 0.145
        case .pulseCapsule: 0.14
        case .standardWindow: 0.14
        case .fullscreenOverlay: 0.10
        }
    }
}

@MainActor
enum WindowMotionAnimator {
    private static let generationTable = NSMapTable<NSWindow, NSNumber>.weakToStrongObjects()
    private static let transformKey = "lumakey.window.motion.transform"

    private static var shouldReduceMotion: Bool {
        SystemDisplayPreferences.shared.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @discardableResult
    private static func bumpGeneration(for window: NSWindow) -> UInt64 {
        let next = currentGeneration(for: window) &+ 1
        generationTable.setObject(NSNumber(value: next), forKey: window)
        return next
    }

    private static func currentGeneration(for window: NSWindow) -> UInt64 {
        generationTable.object(forKey: window)?.uint64Value ?? 0
    }

    static func present(_ window: NSWindow, style: WindowMotionStyle, makeKey: Bool) {
        _ = bumpGeneration(for: window)
        let contentView = window.contentView
        contentView?.wantsLayer = true
        let layer = contentView?.layer
        layer?.removeAnimation(forKey: transformKey)

        guard !shouldReduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.transform = CATransform3DIdentity
            CATransaction.commit()
            window.alphaValue = 1.0
            orderFront(window, makeKey: makeKey)
            return
        }

        let startAlpha: CGFloat = window.isVisible ? min(window.alphaValue, 0.92) : 0.0
        window.alphaValue = startAlpha
        orderFront(window, makeKey: makeKey)
        contentView?.layoutSubtreeIfNeeded()

        if let layer, style != .fullscreenOverlay {
            let bounds = contentView?.bounds ?? NSRect(origin: .zero, size: window.frame.size)
            let fromTransform = centeredTransform(in: bounds, scale: style.enterScale, offsetY: style.enterOffsetY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()

            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = NSValue(caTransform3D: fromTransform)
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.mass = 1.0
            spring.stiffness = 490
            spring.damping = 33
            spring.initialVelocity = 3.5
            spring.duration = min(max(spring.settlingDuration, 0.18), 0.30)
            spring.isRemovedOnCompletion = true
            layer.add(spring, forKey: transformKey)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = style.enterFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.96, 0.32, 1.0)
            window.animator().alphaValue = 1.0
        } completionHandler: { [weak window] in
            MainActor.assumeIsolated {
                window?.invalidateShadow()
            }
        }
    }

    static func dismiss(
        _ window: NSWindow,
        style: WindowMotionStyle,
        immediately: Bool = false,
        onComplete: (@MainActor () -> Void)? = nil
    ) {
        let gen = bumpGeneration(for: window)
        let contentView = window.contentView
        contentView?.wantsLayer = true
        let layer = contentView?.layer
        layer?.removeAnimation(forKey: transformKey)

        guard window.isVisible, !immediately, !shouldReduceMotion else {
            resetVisualState(window)
            window.orderOut(nil)
            onComplete?()
            return
        }

        if let layer, style != .fullscreenOverlay {
            let bounds = contentView?.bounds ?? NSRect(origin: .zero, size: window.frame.size)
            let toTransform = centeredTransform(in: bounds, scale: style.exitScale, offsetY: style.exitOffsetY)
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
            anim.toValue = NSValue(caTransform3D: toTransform)
            anim.duration = style.exitDuration
            anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.68, 0.0)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: transformKey)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = style.exitDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.68, 0.0)
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak window] in
            MainActor.assumeIsolated {
                guard let window, currentGeneration(for: window) == gen else { return }
                window.orderOut(nil)
                resetVisualState(window)
                onComplete?()
            }
        }
    }

    static func closeWindowAnimated(_ window: NSWindow, style: WindowMotionStyle = .standardWindow) {
        dismiss(window, style: style) { [weak window] in
            window?.close()
        }
    }

    static func animateFrame(
        _ window: NSWindow,
        to targetFrame: NSRect,
        duration: TimeInterval = 0.23,
        onComplete: (@MainActor () -> Void)? = nil
    ) {
        guard !shouldReduceMotion, window.isVisible else {
            window.setFrame(targetFrame, display: true, animate: false)
            window.invalidateShadow()
            onComplete?()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.96, 0.32, 1.0)
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak window] in
            MainActor.assumeIsolated {
                window?.invalidateShadow()
                onComplete?()
            }
        }
    }

    private static func orderFront(_ window: NSWindow, makeKey: Bool) {
        if makeKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private static func resetVisualState(_ window: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.contentView?.layer?.removeAnimation(forKey: transformKey)
        window.contentView?.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        window.alphaValue = 1.0
    }

    private static func centeredTransform(in bounds: NSRect, scale: CGFloat, offsetY: CGFloat) -> CATransform3D {
        let cx = bounds.midX
        let cy = bounds.midY
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, cx, cy + offsetY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1.0)
        transform = CATransform3DTranslate(transform, -cx, -cy, 0)
        return transform
    }
}
