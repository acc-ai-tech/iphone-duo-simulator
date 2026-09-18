import UIKit

/// Geometry of the emulated device at one moment (possibly interpolated).
struct DuoGeometry: Equatable {
    var screenSize: CGSize
    var contentFrame: CGRect
    var hingeAxis: DuoHingeAxis
    var angle: Double

    init(layout: DuoLayout, angle: Double) {
        screenSize = layout.screenSize
        contentFrame = layout.contentFrame
        hingeAxis = layout.hingeAxis
        self.angle = angle
    }

    init(screenSize: CGSize, contentFrame: CGRect, hingeAxis: DuoHingeAxis, angle: Double) {
        self.screenSize = screenSize
        self.contentFrame = contentFrame
        self.hingeAxis = hingeAxis
        self.angle = angle
    }
}

/// Root controller that hosts the app's original root controller inside a Duo-sized container.
final class DuoHostViewController: UIViewController {
    /// The app's controller: a child of this host in `.containerChild` mode, or the resized window's root
    /// controller in `.resizeWindow` mode, where the host only draws the device around it.
    weak var contentController: UIViewController?
    /// `nil` in `.resizeWindow` mode: the app keeps its own window and is not reparented.
    private let child: UIViewController?
    unowned let runtime: DuoRuntime
    var config: DuoConfiguration { runtime.config }

    /// Device body (bezel). Snapshots for fold leaves are taken from this view.
    let bezelView = UIView()
    /// Physical screen area; clips content.
    let screenView = UIView()
    /// Visible in the part of the screen that the content does not use (split presets).
    let placeholderView = SplitPlaceholderView()
    /// Container with the exact content size.
    let contentContainer = UIView()
    let hingeView = HingeView()
    let overlay = FoldOverlayView()
    private let infoLabel = UILabel()
    private let previewBadge = UIButton(type: .system)

    private(set) var displayedState: DuoState
    private(set) var geometry: DuoGeometry
    /// Set while an animator drives frames; blocks automatic relayout.
    var isAnimating = false
    /// Called after every layout pass so the window host can follow the content frame.
    var onGeometryChange: ((DuoGeometry) -> Void)?
    private var liveLeaves: LeafSnapshotter?
    private(set) lazy var sideToolbar = SideToolbarController(host: self)
    private(set) lazy var modalPlacement = ModalPlacement(host: self)
    private var lastTraits: (DuoSizeClassRule, DuoPosture, DuoHinge)?

    init(child: UIViewController?, runtime: DuoRuntime) {
        self.child = child
        self.contentController = child
        self.runtime = runtime
        displayedState = runtime.state
        geometry = DuoGeometry(layout: runtime.state.layout(in: runtime.config), angle: runtime.state.hingeAngle)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)

        bezelView.layer.cornerCurve = .continuous
        bezelView.layer.borderColor = UIColor(white: 0.35, alpha: 1).cgColor
        view.addSubview(bezelView)

        screenView.clipsToBounds = true
        screenView.layer.cornerCurve = .continuous
        screenView.backgroundColor = .black
        bezelView.addSubview(screenView)
        screenView.addSubview(placeholderView)

        contentContainer.clipsToBounds = true
        screenView.addSubview(contentContainer)

        screenView.addSubview(sideToolbar.view)

        hingeView.isUserInteractionEnabled = false
        screenView.addSubview(hingeView)

        infoLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        infoLabel.textColor = UIColor(white: 0.75, alpha: 1)
        infoLabel.textAlignment = .center
        view.addSubview(infoLabel)

        overlay.isHidden = true
        overlay.backgroundColor = view.backgroundColor
        view.addSubview(overlay)

        var badge = UIButton.Configuration.filled()
        badge.title = "3D preview only · interaction disabled"
        badge.image = UIImage(systemName: "xmark.circle.fill")
        badge.imagePlacement = .trailing
        badge.imagePadding = 8
        badge.baseBackgroundColor = UIColor.systemOrange.withAlphaComponent(0.95)
        badge.baseForegroundColor = .white
        badge.cornerStyle = .capsule
        badge.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 14, weight: .semibold)
            return attributes
        }
        previewBadge.configuration = badge
        previewBadge.accessibilityHint = "Turns off the 3D view"
        previewBadge.addAction(UIAction { [weak self] _ in self?.runtime.options.show3D = false }, for: .primaryActionTriggered)
        previewBadge.isHidden = true
        view.addSubview(previewBadge)

        if let child {
            addChild(child)
            child.view.frame = contentContainer.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentContainer.addSubview(child.view)
            child.didMove(toParent: self)
        }

        applyTraits(layout: layout(for: displayedState), angle: displayedState.hingeAngle)
        applyStyle()
        sideToolbar.update()

        let tap = UITapGestureRecognizer(target: self, action: #selector(threeFingerDoubleTap))
        tap.numberOfTouchesRequired = 3
        tap.numberOfTapsRequired = 2
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        overlay.frame = view.bounds
        if !isAnimating {
            layoutGeometry(geometry)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        updateAuxiliary()
        sideToolbar.update()
        modalPlacement.start()
    }

    /// The host window changed size (iPad rotation). The content keeps its Duo size, so the new size is
    /// intentionally not forwarded to children.
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }

    override var childForStatusBarStyle: UIViewController? { child }
    override var childForHomeIndicatorAutoHidden: UIViewController? { child }

    // MARK: Keyboard

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        DuoKeyCommands.commands(config: config)
    }

    @objc func duoHandleKeyCommand(_ command: UIKeyCommand) {
        DuoKeyCommands.perform(command, runtime: runtime)
    }

    @objc private func threeFingerDoubleTap() {
        runtime.toggleHUD()
    }

    // MARK: Layout

    func layout(for state: DuoState) -> DuoLayout {
        state.layout(in: config)
    }

    /// Frame of the device body in host view coordinates, and the scale applied to fit the window.
    ///
    /// The content keeps its exact Duo size in points; when the window (for example a Stage Manager window) or the
    /// space below the docked HUD is too small, the whole device is scaled down visually.
    func bezelPlacement(for geometry: DuoGeometry) -> (frame: CGRect, scale: CGFloat) {
        let bezel = config.bezelWidth
        let size = CGSize(width: geometry.screenSize.width + bezel * 2, height: geometry.screenSize.height + bezel * 2)
        let infoHeight: CGFloat = runtime.options.showSizes ? 28 : 0
        let margin: CGFloat = 8

        func fit(in area: CGRect) -> CGFloat {
            min(1, (area.width - margin * 2) / size.width, (area.height - margin * 2 - infoHeight) / size.height)
        }

        var area = view.bounds
        let reserved = runtime.hudTopInset
        if reserved > 0 {
            let belowHUD = area.inset(by: UIEdgeInsets(top: reserved, left: 0, bottom: 0, right: 0))
            // Prefer not to overlap the HUD unless that would shrink the device a lot.
            if fit(in: belowHUD) >= min(fit(in: area), 1) * 0.75 { area = belowHUD }
        }
        let scale = max(fit(in: area), 0.1)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (area.minX + (area.width - scaled.width) / 2).rounded(),
                             y: (area.minY + (area.height - scaled.height - infoHeight) / 2).rounded())
        return (CGRect(origin: origin, size: scaled), scale)
    }

    /// Positions device, screen and content for a geometry and applies hinge visuals and safe area.
    func layoutGeometry(_ geometry: DuoGeometry) {
        self.geometry = geometry
        let bezel = config.bezelWidth
        let placement = bezelPlacement(for: geometry)
        bezelView.transform = .identity
        bezelView.bounds = CGRect(x: 0, y: 0, width: geometry.screenSize.width + bezel * 2, height: geometry.screenSize.height + bezel * 2)
        bezelView.center = CGPoint(x: placement.frame.midX, y: placement.frame.midY)
        bezelView.transform = CGAffineTransform(scaleX: placement.scale, y: placement.scale)
        screenView.frame = CGRect(x: bezel, y: bezel, width: geometry.screenSize.width, height: geometry.screenSize.height)
        placeholderView.frame = screenView.bounds
        placeholderView.contentFrame = geometry.contentFrame
        placeholderView.isHidden = geometry.contentFrame.size == geometry.screenSize
        contentContainer.frame = geometry.contentFrame
        let toolbarWidth = sideToolbar.width
        sideToolbar.view.frame = CGRect(x: geometry.contentFrame.maxX - toolbarWidth, y: geometry.contentFrame.minY,
                                        width: toolbarWidth, height: geometry.contentFrame.height)
        hingeView.frame = screenView.bounds
        hingeView.update(axis: geometry.angle >= config.displaySwitchAngle ? geometry.hingeAxis : .none,
                         angle: geometry.angle, config: config, visible: runtime.options.showHinge)
        infoLabel.frame = CGRect(x: 0, y: bezelView.frame.maxY + 8, width: view.bounds.width, height: 20)
        infoLabel.text = infoText(for: geometry) + (placement.scale < 0.995 ? String(format: " · shown at %.0f%%", placement.scale * 100) : "")
        previewBadge.sizeToFit()
        previewBadge.center = CGPoint(x: bezelView.frame.midX, y: bezelView.frame.maxY - previewBadge.bounds.height / 2 - 16)
        applySafeArea()
        contentContainer.layoutIfNeeded()
        onGeometryChange?(geometry)
    }

    private func applySafeArea() {
        let preset = layout(for: displayedState).safeAreaInsets
        let real = runtime.windowHost?.appWindow.safeAreaInsets ?? contentContainer.safeAreaInsets
        let insets = UIEdgeInsets(top: max(0, preset.top - real.top), left: max(0, preset.left - real.left),
                                  bottom: max(0, preset.bottom - real.bottom),
                                  right: max(0, preset.right - real.right) + sideToolbar.width)
        if let contentController, contentController.additionalSafeAreaInsets != insets {
            contentController.additionalSafeAreaInsets = insets
        }
    }

    private func infoText(for geometry: DuoGeometry) -> String {
        let layout = layout(for: displayedState)
        let size = geometry.contentFrame.size
        let posture = DuoState(hingeAngle: geometry.angle).posture(in: config)
        return "\(layout.preset.id) · \(Int(size.width.rounded()))×\(Int(size.height.rounded())) pt · "
            + "h:\(layout.sizeClass.horizontal.rawValue) v:\(layout.sizeClass.vertical.rawValue) · "
            + "\(posture.rawValue) \(Int(geometry.angle.rounded()))° · \(layout.display.rawValue)"
    }

    // MARK: Traits

    /// Applies size classes and Duo traits to the content.
    ///
    func applyTraits(layout: DuoLayout, angle: Double) {
        var angleState = displayedState
        angleState.hingeAngle = angle
        let posture = angleState.posture(in: config)
        let hingeRect = angle >= config.displaySwitchAngle ? layout.hingeRect : .null
        let hinge = DuoHinge(angle: angle, rect: hingeRect)
        if let last = lastTraits, last.0 == layout.sizeClass, last.1 == posture, last.2 == hinge { return }
        lastTraits = (layout.sizeClass, posture, hinge)

        guard let contentController else { return }
        let overrides = contentController.traitOverrides
        let h: UIUserInterfaceSizeClass = layout.sizeClass.horizontal == .compact ? .compact : .regular
        let v: UIUserInterfaceSizeClass = layout.sizeClass.vertical == .compact ? .compact : .regular
        if !overrides.contains(UITraitHorizontalSizeClass.self) || overrides.horizontalSizeClass != h {
            contentController.traitOverrides.horizontalSizeClass = h
        }
        if !overrides.contains(UITraitVerticalSizeClass.self) || overrides.verticalSizeClass != v {
            contentController.traitOverrides.verticalSizeClass = v
        }
        if !overrides.contains(DuoPostureTrait.self) || overrides[DuoPostureTrait.self] != posture {
            contentController.traitOverrides[DuoPostureTrait.self] = posture
        }
        if !overrides.contains(DuoHingeTrait.self) || overrides[DuoHingeTrait.self] != hinge {
            contentController.traitOverrides[DuoHingeTrait.self] = hinge
        }
    }

    // MARK: Transitions

    /// Makes `state` the displayed state: traits and, if the content size changes, `viewWillTransition(to:with:)`.
    /// Frames are not touched.
    func commitDisplayed(_ state: DuoState, coordinator: DuoTransitionCoordinator?) {
        let oldSize = layout(for: displayedState).contentFrame.size
        displayedState = state
        let newLayout = layout(for: state)
        applyTraits(layout: newLayout, angle: state.hingeAngle)
        if isViewLoaded { sideToolbar.update() }
        if let coordinator, newLayout.contentFrame.size != oldSize {
            contentController?.viewWillTransition(to: newLayout.contentFrame.size, with: coordinator)
        }
    }

    /// Standard UIKit-style transition: traits, `viewWillTransition`, frames animated with `UIView.animate`.
    func performTransition(to state: DuoState, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let coordinator = DuoTransitionCoordinator(duration: duration, containerView: contentContainer)
        commitDisplayed(state, coordinator: coordinator)
        let target = DuoGeometry(layout: layout(for: state), angle: state.hingeAngle)
        coordinator.run(animations: { self.layoutGeometry(target) }, completion: completion)
    }

    /// Duration for a transition, scaled by the angle delta.
    func duration(for animation: DuoAnimation, from: DuoState, to: DuoState) -> TimeInterval {
        let full = animation.duration ?? config.animation.duration
        let delta = abs(to.hingeAngle - from.hingeAngle)
        let sizeChanged = layout(for: from).screenSize != layout(for: to).screenSize
            || layout(for: from).contentFrame != layout(for: to).contentFrame
        let fraction = max(config.animation.minimumDurationFraction, delta / 180)
        return full * (delta == 0 && sizeChanged ? 1 : fraction)
    }

    func transition(from old: DuoState, to new: DuoState, animation: DuoAnimation, completion: @escaping () -> Void) {
        stopLiveLeaves()
        let finish = { [weak self] in
            self?.updateAuxiliary()
            completion()
        }
        let from = displayedState
        switch animation.kind {
        case .none:
            performTransition(to: new, duration: 0, completion: finish)
        case .realistic:
            RealisticAnimator(host: self, from: from, to: new, animation: animation).start(completion: finish)
        }
    }

    // MARK: Options, 3D view

    func optionsDidChange() {
        applyStyle()
        sideToolbar.update()
        view.setNeedsLayout()
        if !isAnimating {
            layoutGeometry(geometry)
            updateAuxiliary()
        }
    }

    private func applyStyle() {
        let showFrame = runtime.options.showFrame
        let radius = config.cornerRadius
        screenView.layer.cornerRadius = radius
        bezelView.layer.cornerRadius = showFrame ? radius + config.bezelWidth : radius
        bezelView.backgroundColor = showFrame ? UIColor(white: 0.16, alpha: 1) : .clear
        bezelView.layer.borderWidth = showFrame ? 1 : 0
        infoLabel.isHidden = !runtime.options.showSizes
    }

    /// Starts or stops the static 3D half-open view depending on options and posture.
    func updateAuxiliary() {
        guard isViewLoaded, !isAnimating else { return }
        let wants3D = runtime.options.show3D
            && displayedState.posture(in: config) == .halfOpen
            && displayedState.activeDisplay(in: config) == .inner
        if wants3D {
            startLiveLeaves()
        } else {
            stopLiveLeaves()
        }
    }

    private func startLiveLeaves() {
        if let liveLeaves {
            liveLeaves.render()
            return
        }
        let snapshotter = LeafSnapshotter(host: self)
        liveLeaves = snapshotter
        screenView.isUserInteractionEnabled = false
        previewBadge.isHidden = false
        snapshotter.start()
    }

    func stopLiveLeaves() {
        guard let liveLeaves else { return }
        liveLeaves.stop()
        self.liveLeaves = nil
        screenView.isUserInteractionEnabled = true
        previewBadge.isHidden = true
        overlay.hide()
    }

    /// `true` while the device is drawn as 3D snapshot leaves (static half-open view).
    var isShowingLeaves: Bool { liveLeaves != nil }

    /// Puts the fold overlay above the device (and the 3D badge above the overlay).
    func raiseOverlay() {
        overlay.superview?.bringSubviewToFront(overlay)
        previewBadge.superview?.bringSubviewToFront(previewBadge)
    }

    /// Moves the fold overlay and the 3D badge into another view, used by window mode to draw them above the app's
    /// own window. Their frames keep using screen coordinates, which both windows share.
    func moveOverlay(to container: UIView) {
        container.addSubview(overlay)
        container.addSubview(previewBadge)
        overlay.frame = container.bounds
    }

    /// Lays the moved overlay out; called by the window host after each layout pass.
    func layoutMovedOverlay(in container: UIView) {
        overlay.frame = container.bounds
        previewBadge.sizeToFit()
        previewBadge.center = CGPoint(x: bezelView.frame.midX,
                                      y: bezelView.frame.maxY - previewBadge.bounds.height / 2 - 16)
    }

    // MARK: Snapshots

    /// Image of the device body (bezel, screen, hinge line, content).
    func snapshotDevice(afterScreenUpdates: Bool) -> UIImage {
        let windowHost = runtime.windowHost
        let content = windowHost?.contentSnapshot(afterScreenUpdates: afterScreenUpdates)
        let renderer = UIGraphicsImageRenderer(bounds: bezelView.bounds)
        return renderer.image { _ in
            _ = bezelView.drawHierarchy(in: bezelView.bounds, afterScreenUpdates: afterScreenUpdates)
            // In window mode the app lives in its own window, so it is drawn into the content area here.
            if let content {
                let frame = screenView.convert(geometry.contentFrame, to: bezelView)
                content.draw(in: frame)
            }
        }
    }
}

/// Fills the unused part of the inner screen in split presets.
final class SplitPlaceholderView: UIView {
    /// Barely visible glyph marking the area of another app.
    private let icon = UIImageView(image: UIImage(systemName: "square.grid.2x2"))
    var contentFrame: CGRect = .zero { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        icon.tintColor = UIColor(white: 1, alpha: 0.12)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        icon.contentMode = .center
        icon.isAccessibilityElement = true
        icon.accessibilityLabel = "Other app"
        addSubview(icon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Center the icon in the part that the content does not cover.
        let content = contentFrame
        var free = bounds
        if content.width < bounds.width {
            free = CGRect(x: content.maxX, y: 0, width: bounds.width - content.maxX, height: bounds.height)
        } else if content.height < bounds.height {
            free = CGRect(x: 0, y: content.maxY, width: bounds.width, height: bounds.height - content.maxY)
        }
        icon.frame = free
    }
}

final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 10, dy: 5))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 20, height: size.height + 10)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }
}
