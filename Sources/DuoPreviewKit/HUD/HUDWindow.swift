import SwiftUI
import UIKit

/// Window that only receives touches on the HUD itself; everything else passes through to the app.
final class HUDWindow: UIWindow {
    weak var panel: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let panel, !panel.isHidden else { return nil }
        let local = convert(point, to: panel)
        guard panel.bounds.contains(local) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Root controller of the HUD window: a draggable panel that collapses into a round button.
final class HUDRootViewController: UIViewController {
    unowned let runtime: DuoRuntime
    let model: HUDModel
    let panel = UIView()
    private let hosting: UIHostingController<HUDView>
    private let collapsedButton = UIButton(type: .system)
    private var didPlacePanel = false

    private let maxExpandedWidth: CGFloat = 1016
    private let collapsedSize = CGSize(width: 60, height: 60)

    init(runtime: DuoRuntime, model: HUDModel) {
        self.runtime = runtime
        self.model = model
        hosting = UIHostingController(rootView: HUDView(model: model))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        panel.layer.cornerRadius = 14
        panel.layer.shadowOpacity = 0.4
        panel.layer.shadowRadius = 10
        panel.layer.shadowOffset = .zero
        view.addSubview(panel)

        addChild(hosting)
        // Report content size changes (e.g. switching to the advanced panel) via preferredContentSizeDidChange.
        hosting.sizingOptions = .preferredContentSize
        hosting.view.backgroundColor = .clear
        hosting.view.layer.cornerRadius = 14
        hosting.view.clipsToBounds = true
        panel.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        collapsedButton.setImage(UIImage(systemName: "rectangle.split.2x1"), for: .normal)
        collapsedButton.tintColor = .white
        collapsedButton.backgroundColor = UIColor.systemIndigo
        collapsedButton.layer.cornerRadius = collapsedSize.width / 2
        collapsedButton.addAction(UIAction { [weak self] _ in self?.model.collapsed = false }, for: .primaryActionTriggered)
        panel.addSubview(collapsedButton)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        panel.addGestureRecognizer(pan)

        model.onCollapsedChange = { [weak self] in
            // Let SwiftUI apply the new content first so the measured height is current.
            DispatchQueue.main.async { self?.updateCollapsed(animated: true) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0 else { return }
        let compact = view.bounds.width < 760
        if model.compact != compact {
            model.compact = compact
            didPlacePanel = false
        }
        if !didPlacePanel {
            didPlacePanel = true
            updateCollapsed(animated: false)
        } else {
            clampPanel()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.didPlacePanel = false
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }

    /// Expanded: wide panel docked at the top center. Collapsed: round button in the top right corner.
    private func updateCollapsed(animated: Bool) {
        let collapsed = model.collapsed
        let bounds = view.bounds
        let top = view.safeAreaInsets.top + 6
        let frame: CGRect
        if collapsed {
            frame = CGRect(x: bounds.maxX - collapsedSize.width - 16, y: top, width: collapsedSize.width, height: collapsedSize.height)
        } else {
            let width = model.compact ? bounds.width - 16 : min(bounds.width - 16, maxExpandedWidth)
            let height = ceil(hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            frame = CGRect(x: ((bounds.width - width) / 2).rounded(), y: top, width: width, height: height)
        }
        let changes = {
            self.panel.frame = frame
            self.hosting.view.frame = self.panel.bounds
            self.collapsedButton.frame = self.panel.bounds
            self.hosting.view.alpha = collapsed ? 0 : 1
            self.collapsedButton.alpha = collapsed ? 1 : 0
            self.clampPanel()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
    }

    private func clampPanel() {
        guard view.bounds.width > 0 else { return }
        var frame = panel.frame
        frame.origin.x = min(max(frame.origin.x, 8), view.bounds.width - frame.width - 8)
        frame.origin.y = min(max(frame.origin.y, view.safeAreaInsets.top + 4), view.bounds.height - frame.height - 8)
        panel.frame = frame
        updateReservedInset()
    }

    /// Tells the host how much space the docked panel takes at the top.
    func updateReservedInset() {
        let docked = !model.collapsed && !(view.window?.isHidden ?? true) && panel.frame.minY < view.bounds.height / 4
        runtime.hudTopInset = docked ? panel.frame.maxY + 8 : 0
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view)
        panel.center = CGPoint(x: panel.center.x + translation.x, y: panel.center.y + translation.y)
        pan.setTranslation(.zero, in: view)
        if pan.state == .ended || pan.state == .cancelled {
            clampPanel()
        }
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        guard didPlacePanel, !model.collapsed else { return }
        updateCollapsed(animated: true)
    }

    // MARK: Keyboard (when a HUD text field is focused)

    override var keyCommands: [UIKeyCommand]? {
        DuoKeyCommands.commands(config: runtime.config)
    }

    @objc func duoHandleKeyCommand(_ command: UIKeyCommand) {
        DuoKeyCommands.perform(command, runtime: runtime)
    }
}

extension HUDRootViewController: UIGestureRecognizerDelegate {
    /// Drag only from the header strip (or anywhere when collapsed) so sliders keep working.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        model.collapsed || gestureRecognizer.location(in: panel).y < (model.compact ? 44 : 56)
    }
}

/// Owns the HUD window.
@MainActor
final class HUDController {
    let window: HUDWindow
    let model: HUDModel

    init(scene: UIWindowScene, runtime: DuoRuntime) {
        model = HUDModel(runtime: runtime)
        window = HUDWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        let root = HUDRootViewController(runtime: runtime, model: model)
        window.rootViewController = root
        window.panel = root.panel
        window.backgroundColor = .clear
    }

    func setVisible(_ visible: Bool) {
        window.isHidden = !visible
        (window.rootViewController as? HUDRootViewController)?.updateReservedInset()
    }

    func stateDidChange() {
        model.refresh()
    }
}
