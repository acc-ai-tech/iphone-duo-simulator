import UIKit

/// Keeps modal presentations inside the far half of the inner screen while the device is half-open.
///
/// UIKit positions sheets, form sheets and alerts against the window, not against the emulated screen, and there is no
/// public hook to change that. As a workaround the container view UIKit creates for a presentation is moved and resized
/// to the target half; the presented controller lays out inside it as usual.
///
/// Best effort: some presentations (popovers anchored to a source view, the keyboard) are still placed by UIKit.
@MainActor
final class ModalPlacement {
    private unowned let host: DuoHostViewController
    private var displayLink: CADisplayLink?
    private var adjusted = NSHashTable<UIView>.weakObjects()

    init(host: DuoHostViewController) {
        self.host = host
    }

    /// Area that modals should occupy, in window coordinates, or `nil` when they should be left alone.
    private var targetFrame: CGRect? {
        guard host.runtime.options.modalsOnHalf, host.isViewLoaded, let window = host.view.window else { return nil }
        let layout = host.layout(for: host.displayedState)
        // Only while half-open: fully open behaves like one screen, so modals stay where UIKit puts them.
        guard layout.display == .inner, layout.posture == .halfOpen, !layout.hingeRectInScreen.isNull else { return nil }

        // The half past the hinge: right of it in landscape, below it in portrait.
        let hinge = layout.hingeRectInScreen
        let half: CGRect
        switch layout.hingeAxis {
        case .vertical:
            half = CGRect(x: hinge.maxX, y: 0,
                          width: layout.screenSize.width - hinge.maxX, height: layout.screenSize.height)
        case .horizontal:
            half = CGRect(x: 0, y: hinge.maxY,
                          width: layout.screenSize.width, height: layout.screenSize.height - hinge.maxY)
        case .none:
            return nil
        }
        return host.screenView.convert(half, to: window)
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        restoreAll()
    }

    isolated deinit {
        displayLink?.invalidate()
    }

    @objc private func tick() {
        guard let window = host.view.window else { return }
        guard let target = targetFrame else {
            restoreAll()
            return
        }
        let leaf = leafTransform()
        // UIKit puts the app and each presentation into its own container view in the window. The one holding the
        // host is left alone; the others are the presentations.
        for view in window.subviews where !host.view.isDescendant(of: view) {
            if !CATransform3DIsIdentity(view.layer.transform) { view.layer.transform = CATransform3DIdentity }
            if view.frame != target {
                view.frame = target
                view.clipsToBounds = true
            }
            // While the static 3D view is on, fold the presentation with the leaf it sits on.
            if let leaf {
                view.layer.anchorPoint = leaf.anchor
                view.center = leaf.hingePoint
                view.layer.transform = leaf.transform
            } else if view.layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
                view.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                view.center = CGPoint(x: target.midX, y: target.midY)
            }
            adjusted.add(view)
        }
    }

    /// Rotation of the leaf the far half sits on, or `nil` when the flat content is shown.
    private func leafTransform() -> (transform: CATransform3D, anchor: CGPoint, hingePoint: CGPoint)? {
        guard host.isShowingLeaves, let window = host.view.window else { return nil }
        let config = host.config
        let layout = host.layout(for: host.displayedState)
        let rotation = config.innerLeafRotation(angle: host.displayedState.hingeAngle) * .pi / 180
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / config.animation.perspective

        let hinge = layout.hingeRectInScreen
        switch layout.hingeAxis {
        case .vertical:
            let point = host.screenView.convert(CGPoint(x: hinge.midX, y: hinge.midY), to: window)
            return (CATransform3DConcat(CATransform3DMakeRotation(-rotation, 0, 1, 0), perspective),
                    CGPoint(x: 0, y: 0.5), point)
        case .horizontal:
            let point = host.screenView.convert(CGPoint(x: hinge.midX, y: hinge.midY), to: window)
            return (CATransform3DConcat(CATransform3DMakeRotation(rotation, 1, 0, 0), perspective),
                    CGPoint(x: 0.5, y: 0), point)
        case .none:
            return nil
        }
    }

    private func restoreAll() {
        guard let window = host.view.window else { return }
        for view in adjusted.allObjects where view.window === window {
            view.layer.transform = CATransform3DIdentity
            view.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            view.frame = window.bounds
            view.clipsToBounds = false
        }
        adjusted.removeAllObjects()
    }
}
