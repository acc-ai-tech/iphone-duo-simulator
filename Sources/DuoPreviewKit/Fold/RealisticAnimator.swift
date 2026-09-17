import UIKit

/// Drives a display link from 0 to 1 over a duration.
@MainActor
final class FrameClock {
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private let duration: TimeInterval
    private let tick: (Double) -> Void
    private let completion: () -> Void

    init(duration: TimeInterval, tick: @escaping (Double) -> Void, completion: @escaping () -> Void) {
        self.duration = duration
        self.tick = tick
        self.completion = completion
    }

    func run() {
        guard duration > 0 else {
            tick(1)
            completion()
            return
        }
        start = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        tick(0)
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = min((CACurrentMediaTime() - start) / duration, 1)
        tick(t)
        if t >= 1 {
            link.invalidate()
            self.link = nil
            completion()
        }
    }

    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

/// `.realistic`: snapshot leaves rotate in 3D; live content is switched to the other display at `displaySwitchAngle`.
@MainActor
final class RealisticAnimator {
    private let host: DuoHostViewController
    private let from: DuoState
    private let to: DuoState
    private let animation: DuoAnimation
    private var clock: FrameClock?
    private var switched = false
    private var useBlur = false
    private var retainSelf: RealisticAnimator?

    init(host: DuoHostViewController, from: DuoState, to: DuoState, animation: DuoAnimation) {
        self.host = host
        self.from = from
        self.to = to
        self.animation = animation
    }

    func start(completion: @escaping () -> Void) {
        let config = host.config
        let fromLayout = host.layout(for: from)
        let toLayout = host.layout(for: to)
        let crosses = fromLayout.display != toLayout.display
        let duration = host.duration(for: animation, from: from, to: to)

        // Same display, different geometry (orientation/split/custom): regular animated UIKit transition.
        if !crosses && (fromLayout.screenSize != toLayout.screenSize || fromLayout.contentFrame != toLayout.contentFrame) {
            host.performTransition(to: to, duration: duration, completion: completion)
            return
        }
        guard from.hingeAngle != to.hingeAngle else {
            host.performTransition(to: to, duration: 0, completion: completion)
            return
        }

        retainSelf = self
        useBlur = host.runtime.options.blurOnFold && config.animation.blurRadius > 0
        host.isAnimating = true
        showLeaves(for: from, afterScreenUpdates: false)

        let a0 = from.hingeAngle, a1 = to.hingeAngle
        let sw = config.displaySwitchAngle
        clock = FrameClock(duration: duration, tick: { [unowned self] t in
            let angle = a0 + (a1 - a0) * FrameClock.easeInOut(t)
            if crosses && !switched && ((a1 < a0 && angle < sw) || (a1 > a0 && angle >= sw)) {
                switched = true
                var mid = to
                mid.hingeAngle = angle
                host.performTransition(to: mid, duration: 0)
                showLeaves(for: mid, afterScreenUpdates: true)
            }
            let display = DuoState(hingeAngle: angle).activeDisplay(in: config)
            let rotation = display == .outer ? config.outerLeafRotation(angle: angle) : config.innerLeafRotation(angle: angle)
            let ramp = max(config.animation.blurRampFraction, 0.01)
            let blur = useBlur ? min(t / ramp, 1) : 0
            host.overlay.render(rotation: rotation, shadeOpacity: config.animation.shadeOpacity, blur: blur)
        }, completion: { [unowned self] in
            host.isAnimating = false
            host.performTransition(to: to, duration: 0)
            clock = nil
            guard useBlur, config.animation.blurFadeOut > 0 else {
                host.overlay.hide()
                retainSelf = nil
                completion()
                return
            }
            // Blurred snapshot of the final layout, then dissolve into the live content.
            showLeaves(for: to, afterScreenUpdates: true)
            host.overlay.render(rotation: 0, shadeOpacity: 0, blur: 1)
            UIView.animate(withDuration: config.animation.blurFadeOut, delay: 0, options: [.curveEaseOut]) {
                self.host.overlay.alpha = 0
            } completion: { _ in
                self.host.overlay.hide()
                self.retainSelf = nil
                completion()
            }
        })
        clock?.run()
    }

    private func showLeaves(for state: DuoState, afterScreenUpdates: Bool) {
        let layout = host.layout(for: state)
        host.layoutGeometry(DuoGeometry(layout: layout, angle: state.hingeAngle))
        let image = host.snapshotDevice(afterScreenUpdates: afterScreenUpdates)
        let blurred = useBlur ? FoldOverlayView.blurred(image, radius: host.config.animation.blurRadius) : nil
        let axis: DuoHingeAxis = layout.display == .outer ? .none : (layout.hingeAxis == .none ? .vertical : layout.hingeAxis)
        host.overlay.configure(image: image, blurred: blurred, frame: host.bezelView.frame, axis: axis,
                               perspective: host.config.animation.perspective)
        host.raiseOverlay()
    }
}
