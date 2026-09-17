import UIKit

/// Minimal `UIViewControllerTransitionCoordinator` passed to `viewWillTransition(to:with:)` of the content.
/// Alongside animations run inside the emulator's own animation block; completions run when it ends.
@MainActor
final class DuoTransitionCoordinator: NSObject, UIViewControllerTransitionCoordinator {
    typealias Block = (any UIViewControllerTransitionCoordinatorContext) -> Void

    let transitionDuration: TimeInterval
    let containerView: UIView
    private var alongside: [Block] = []
    private var completions: [Block] = []
    private var didFinish = false

    init(duration: TimeInterval, containerView: UIView) {
        self.transitionDuration = duration
        self.containerView = containerView
    }

    // MARK: UIViewControllerTransitionCoordinatorContext

    var isAnimated: Bool { transitionDuration > 0 }
    var presentationStyle: UIModalPresentationStyle { .none }
    var initiallyInteractive: Bool { false }
    var isInterruptible: Bool { false }
    var isInteractive: Bool { false }
    var isCancelled: Bool { false }
    private(set) var percentComplete: CGFloat = 0
    var completionVelocity: CGFloat { 1 }
    var completionCurve: UIView.AnimationCurve { .easeInOut }
    var targetTransform: CGAffineTransform { .identity }

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { nil }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { nil }

    // MARK: UIViewControllerTransitionCoordinator

    func animate(alongsideTransition animation: Block?, completion: Block? = nil) -> Bool {
        animation.map { alongside.append($0) }
        completion.map { completions.append($0) }
        return true
    }

    func animateAlongsideTransition(in view: UIView?, animation: Block?, completion: Block? = nil) -> Bool {
        animate(alongsideTransition: animation, completion: completion)
    }

    func notifyWhenInteractionEnds(_ handler: @escaping Block) {}
    func notifyWhenInteractionChanges(_ handler: @escaping Block) {}

    // MARK: Driving

    /// Runs `animations` together with registered alongside blocks, then completions.
    func run(animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
        let body = { [self] in
            animations()
            runAlongside()
        }
        if isAnimated {
            UIView.animate(withDuration: transitionDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction],
                           animations: body) { [self] _ in
                finish()
                completion?()
            }
        } else {
            UIView.performWithoutAnimation(body)
            finish()
            completion?()
        }
    }

    /// Starts alongside animations for a transition whose frames are driven manually (display link).
    func beginManual() {
        if isAnimated {
            UIView.animate(withDuration: transitionDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.runAlongside()
            }
        } else {
            UIView.performWithoutAnimation { runAlongside() }
        }
    }

    func updateProgress(_ progress: CGFloat) {
        percentComplete = progress
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        percentComplete = 1
        let blocks = completions
        completions = []
        blocks.forEach { $0(self) }
    }

    private func runAlongside() {
        let blocks = alongside
        alongside = []
        blocks.forEach { $0(self) }
    }
}
