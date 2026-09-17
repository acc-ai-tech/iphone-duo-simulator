import UIKit

/// `.continuous`: live content, frame interpolated every frame (or in N discrete steps) with a flat hinge indication.
@MainActor
final class ContinuousAnimator {
    private let host: DuoHostViewController
    private let from: DuoState
    private let to: DuoState
    private let animation: DuoAnimation
    private var clock: FrameClock?
    private var retainSelf: ContinuousAnimator?

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
        let duration = host.duration(for: animation, from: from, to: to)
        let start = host.geometry
        let axis = toLayout.hingeAxis != .none ? toLayout.hingeAxis : fromLayout.hingeAxis

        retainSelf = self
        host.isAnimating = true
        let coordinator = DuoTransitionCoordinator(duration: duration, containerView: host.contentContainer)
        host.commitDisplayed(to, coordinator: coordinator)
        coordinator.beginManual()

        var frames = 0
        let startTime = CACurrentMediaTime()
        let apply: (Double) -> Void = { [unowned self] t in
            frames += 1
            let angle = start.angle + (to.hingeAngle - start.angle) * t
            let geometry = DuoGeometry(
                screenSize: lerp(start.screenSize, toLayout.screenSize, t),
                contentFrame: lerp(start.contentFrame, toLayout.contentFrame, t),
                hingeAxis: axis,
                angle: angle
            )
            coordinator.updateProgress(t)
            host.applyTraits(layout: toLayout, angle: angle, throttleHinge: true)
            host.layoutGeometry(geometry)
        }
        let finish: () -> Void = { [unowned self] in
            let elapsed = CACurrentMediaTime() - startTime
            if animation.steps == nil, elapsed > 0 {
                duoPrint(String(format: "continuous: %d frames in %.2fs (%.0f fps)", frames, elapsed, Double(frames) / elapsed))
            }
            host.isAnimating = false
            host.layoutGeometry(DuoGeometry(layout: toLayout, angle: to.hingeAngle))
            host.applyTraits(layout: toLayout, angle: to.hingeAngle)
            coordinator.finish()
            clock = nil
            retainSelf = nil
            completion()
        }

        if let steps = animation.steps, steps > 0 {
            let pause = config.animation.continuousStepPause
            Task { @MainActor in
                for i in 1...steps {
                    apply(Double(i) / Double(steps))
                    try? await Task.sleep(for: .seconds(pause))
                }
                finish()
            }
        } else {
            clock = FrameClock(duration: duration, tick: { apply(FrameClock.easeInOut($0)) }, completion: finish)
            clock?.run()
        }
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
    (a + (b - a) * t).rounded()
}

private func lerp(_ a: CGSize, _ b: CGSize, _ t: Double) -> CGSize {
    CGSize(width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

private func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
           width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}
