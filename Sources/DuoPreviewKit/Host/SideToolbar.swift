import UIKit

/// Moves navigation bar and toolbar buttons of the content into a vertical strip on the right edge of the screen.
///
/// Enabled for presets with `"sideToolbar": true` in JSON while the `sideToolbar` option is on. The original bars are
/// hidden (`setNavigationBarHidden` / `setToolbarHidden`) and restored when the state changes; the content receives a
/// right safe area inset equal to `sideToolbarWidth`.
///
/// Limitations (public API only): system bar items (`UIBarButtonItem(systemItem:)`) expose no image or title, so they
/// are shown by accessibility label or a snapshot; custom views that are not `UIControl` cannot be triggered; SwiftUI
/// may show its bars again on updates, so hiding is re-applied on every scan.
@MainActor
final class SideToolbarController {
    private unowned let host: DuoHostViewController
    let view = SideToolbarView()
    private(set) var isActive = false
    private var timer: Timer?
    private var signature = ""
    private var hiddenBars: [ObjectIdentifier: HiddenBars] = [:]
    private var snapshots: [ObjectIdentifier: UIImage] = [:]

    private struct HiddenBars {
        weak var navigation: UINavigationController?
        var navigationBarWasHidden: Bool
        var toolbarWasHidden: Bool
    }

    init(host: DuoHostViewController) {
        self.host = host
    }

    var width: CGFloat { isActive ? host.config.sideToolbarWidth : 0 }

    /// Activates or deactivates for the displayed state and options.
    func update() {
        let layout = host.layout(for: host.displayedState)
        // Only flat states: outer (closed) or fully open inner; half-open keeps the app's own bars.
        let flat = layout.display == .outer || layout.posture == .open
        let shouldBeActive = host.runtime.options.sideToolbar && layout.preset.sideToolbar && flat
            && host.displayedState.customSize == nil
        guard shouldBeActive != isActive else {
            if isActive { scan() }
            return
        }
        isActive = shouldBeActive
        view.isHidden = !shouldBeActive
        if shouldBeActive {
            scan()
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            }
        } else {
            timer?.invalidate()
            timer = nil
            restoreAll()
            signature = ""
            view.setGroups([])
        }
    }

    isolated deinit {
        timer?.invalidate()
    }

    // MARK: Scanning

    private func scan() {
        guard isActive else { return }
        let navigations = visibleNavigationControllers()
        let alive = Set(navigations.map(ObjectIdentifier.init))

        // Restore bars of controllers that are no longer on screen (popped from a split view, replaced, etc.).
        for (id, record) in hiddenBars where !alive.contains(id) {
            if let navigation = record.navigation { restore(navigation, record) }
            hiddenBars[id] = nil
        }

        var groups: [SideToolbarView.Group] = []
        var newSignature = ""
        for navigation in navigations {
            let id = ObjectIdentifier(navigation)
            if hiddenBars[id] == nil {
                // Snapshot custom views before hiding, while they are still rendered.
                cacheSnapshots(for: navigation)
                hiddenBars[id] = HiddenBars(navigation: navigation,
                                            navigationBarWasHidden: navigation.isNavigationBarHidden,
                                            toolbarWasHidden: navigation.isToolbarHidden)
            }
            let record = hiddenBars[id]!
            let searching = navigation.topViewController?.navigationItem.searchController?.isActive == true
            if searching {
                // The search field lives in the navigation bar: keep it visible while searching.
                if navigation.isNavigationBarHidden { navigation.setNavigationBarHidden(false, animated: true) }
            } else if !navigation.isNavigationBarHidden {
                navigation.setNavigationBarHidden(true, animated: false)
            }
            if !navigation.isToolbarHidden { navigation.setToolbarHidden(true, animated: false) }

            let group = makeGroup(for: navigation, record: record)
            newSignature += group.signature + "|"
            if !group.buttons.isEmpty { groups.append(group) }
        }

        if newSignature != signature {
            signature = newSignature
            view.setGroups(groups)
        }
        view.updateClock()
    }

    private func visibleNavigationControllers() -> [UINavigationController] {
        var result: [UINavigationController] = []
        let container = host.contentContainer
        func visit(_ controller: UIViewController) {
            guard controller.isViewLoaded, let view = controller.view, view.window != nil, !view.isHidden, view.alpha > 0.01 else {
                return
            }
            if let navigation = controller as? UINavigationController {
                let frame = view.convert(view.bounds, to: container).intersection(container.bounds)
                if !frame.isNull, frame.width > 1, frame.height > 1, navigation.presentingViewController == nil {
                    result.append(navigation)
                }
                if let top = navigation.topViewController { top.children.forEach(visit) }
                return
            }
            controller.children.forEach(visit)
        }
        visit(host.content)
        return result
    }

    private func restoreAll() {
        for record in hiddenBars.values {
            if let navigation = record.navigation { restore(navigation, record) }
        }
        hiddenBars.removeAll()
        snapshots.removeAll()
    }

    private func restore(_ navigation: UINavigationController, _ record: HiddenBars) {
        navigation.setNavigationBarHidden(record.navigationBarWasHidden, animated: false)
        navigation.setToolbarHidden(record.toolbarWasHidden, animated: false)
    }

    private func cacheSnapshots(for navigation: UINavigationController) {
        guard let item = navigation.topViewController?.navigationItem else { return }
        for barItem in barItems(of: item) {
            guard let custom = barItem.customView, custom.window != nil, custom.bounds.width > 0, custom.bounds.height > 0 else {
                continue
            }
            snapshots[ObjectIdentifier(barItem)] = UIGraphicsImageRenderer(bounds: custom.bounds).image { _ in
                _ = custom.drawHierarchy(in: custom.bounds, afterScreenUpdates: false)
            }
        }
    }

    // MARK: Buttons

    private func barItems(of item: UINavigationItem) -> [UIBarButtonItem] {
        let leading = item.leadingItemGroups.flatMap(\.barButtonItems)
        let trailing = item.trailingItemGroups.flatMap(\.barButtonItems)
        var items = (leading.isEmpty ? item.leftBarButtonItems ?? [] : leading)
            + (trailing.isEmpty ? item.rightBarButtonItems ?? [] : trailing)
        var seen = Set<ObjectIdentifier>()
        items = items.filter { seen.insert(ObjectIdentifier($0)).inserted }
        return items
    }

    private func makeGroup(for navigation: UINavigationController, record: HiddenBars) -> SideToolbarView.Group {
        let top = navigation.topViewController
        let item = top?.navigationItem
        let title = item?.title ?? top?.title
        var buttons: [UIButton] = []
        var signature = "\(ObjectIdentifier(navigation).hashValue):\(navigation.viewControllers.count):\(title ?? "")"

        if !record.navigationBarWasHidden {
            if navigation.viewControllers.count > 1, item?.hidesBackButton != true {
                let previous = navigation.viewControllers[navigation.viewControllers.count - 2]
                let backTitle = previous.navigationItem.backButtonTitle ?? previous.navigationItem.title ?? previous.title
                buttons.append(SideToolbarView.button(image: UIImage(systemName: "chevron.backward"),
                                                      label: backTitle.map { "Back to \($0)" } ?? "Back") { [weak navigation] in
                    navigation?.popViewController(animated: true)
                })
                signature += ":back"
            }
            if let split = navigation.splitViewController, !split.isCollapsed, split.viewController(for: .secondary) === navigation
                || split.viewController(for: .supplementary) === navigation {
                let sidebarHidden = split.displayMode == .secondaryOnly
                buttons.append(SideToolbarView.button(image: UIImage(systemName: "sidebar.leading"),
                                                      label: "Toggle sidebar") { [weak split] in
                    guard let split else { return }
                    if split.displayMode == .secondaryOnly { split.show(.primary) } else { split.hide(.primary) }
                })
                signature += ":sidebar\(sidebarHidden)"
            }
            if let search = item?.searchController {
                buttons.append(SideToolbarView.button(image: UIImage(systemName: "magnifyingglass"),
                                                      label: "Search") { [weak navigation, weak search] in
                    navigation?.setNavigationBarHidden(false, animated: true)
                    search?.isActive = true
                    DispatchQueue.main.async { search?.searchBar.becomeFirstResponder() }
                })
                signature += ":search"
            }
            if let item {
                for barItem in barItems(of: item) {
                    if let button = makeButton(for: barItem) {
                        buttons.append(button)
                        signature += ":\(ObjectIdentifier(barItem).hashValue)\(barItem.isEnabled)\(barItem.title ?? "")"
                    }
                }
            }
        }
        if !record.toolbarWasHidden, let toolbarItems = top?.toolbarItems {
            for barItem in toolbarItems {
                if let button = makeButton(for: barItem) {
                    buttons.append(button)
                    signature += ":t\(ObjectIdentifier(barItem).hashValue)\(barItem.isEnabled)"
                }
            }
        }
        return SideToolbarView.Group(buttons: buttons, signature: signature)
    }

    private func makeButton(for item: UIBarButtonItem) -> UIButton? {
        if item.isHidden { return nil }
        let image = item.image ?? item.primaryAction?.image
        let text = item.title ?? item.primaryAction?.title
        let snapshot = snapshots[ObjectIdentifier(item)]
        let hasBehavior = item.primaryAction != nil || item.action != nil || item.menu != nil || item.customView != nil
        // Items without any content or behavior are spacers.
        guard hasBehavior || image != nil || text != nil else { return nil }

        let label = [item.accessibilityLabel, text].compactMap { $0 }.first { !$0.isEmpty }
        // Icons only: text-only items get a letter symbol ("e.circle" for "Edit"), unknown ones a placeholder.
        let letter = (text ?? label)?.lowercased().first { $0.isLetter && $0.isASCII }
        let fallback = letter.flatMap { UIImage(systemName: "\($0).circle") } ?? UIImage(systemName: "questionmark.circle")
        let button = SideToolbarView.button(
            image: image ?? snapshot?.withRenderingMode(.alwaysOriginal) ?? fallback,
            label: label ?? "Bar item"
        ) { [weak item] in
            guard let item else { return }
            if let action = item.primaryAction {
                action.performWithSender(item, target: nil)
            } else if let selector = item.action {
                UIApplication.shared.sendAction(selector, to: item.target, from: item, for: nil)
            } else if let control = item.customView as? UIControl {
                control.sendActions(for: .primaryActionTriggered)
                control.sendActions(for: .touchUpInside)
            }
        }
        if let menu = item.menu {
            button.menu = menu
            button.showsMenuAsPrimaryAction = item.primaryAction == nil && item.action == nil
        }
        button.isEnabled = item.isEnabled
        if let tint = item.tintColor { button.tintColor = tint }
        return button
    }
}

/// Vertical strip with grouped buttons.
final class SideToolbarView: UIView {
    struct Group {
        var buttons: [UIButton]
        var signature: String
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    /// Dashed vertical line marking where the added right safe area begins.
    private let boundary = CAShapeLayer()
    /// Status bar stand-in at the top of the strip: time and Wi‑Fi.
    private let status = UIStackView()
    private let clock = UILabel()
    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        // Transparent: the content's own background extends under the right safe area, so the strip matches it.
        backgroundColor = .clear
        boundary.fillColor = UIColor.clear.cgColor
        boundary.lineWidth = 1
        boundary.lineDashPattern = [4, 4]
        layer.addSublayer(boundary)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SideToolbarView, _: UITraitCollection) in
            view.setNeedsLayout()
        }
        clock.font = .systemFont(ofSize: 15, weight: .semibold)
        clock.textColor = .label
        clock.textAlignment = .center
        clock.adjustsFontSizeToFitWidth = true
        let wifi = WifiRingView()
        wifi.translatesAutoresizingMaskIntoConstraints = false
        wifi.widthAnchor.constraint(equalToConstant: 34).isActive = true
        wifi.heightAnchor.constraint(equalToConstant: 34).isActive = true
        status.axis = .vertical
        status.alignment = .center
        status.spacing = 4
        status.addArrangedSubview(clock)
        status.addArrangedSubview(wifi)
        status.isAccessibilityElement = false
        addSubview(status)
        updateClock()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        scrollView.addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.5, y: bounds.height))
        boundary.path = path.cgPath
        boundary.frame = bounds
        boundary.strokeColor = UIColor.label.withAlphaComponent(0.3).resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()

        let topInset: CGFloat = 20
        let statusHeight: CGFloat = topInset + 60
        // Column of pill width, pinned to the right edge with a margin.
        let rightInset: CGFloat = 14
        // Never cross the safe area line at x = 0, even if the strip is configured narrower.
        let columnX = max(bounds.width - rightInset - Self.pillWidth, 3)
        status.frame = CGRect(x: columnX, y: topInset, width: Self.pillWidth, height: statusHeight - topInset)
        scrollView.frame = CGRect(x: 0, y: statusHeight, width: bounds.width, height: max(bounds.height - statusHeight, 0))
        let size = stack.systemLayoutSizeFitting(CGSize(width: Self.pillWidth, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: columnX, y: 12, width: Self.pillWidth, height: size.height)
        scrollView.contentSize = CGSize(width: bounds.width, height: size.height + 24)
    }

    func updateClock() {
        let text = clockFormatter.string(from: Date())
        if clock.text != text { clock.text = text }
    }

    func setGroups(_ groups: [Group]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.spacing = 12
        for group in groups {
            stack.addArrangedSubview(Self.pill(with: group.buttons))
        }
        setNeedsLayout()
    }

    /// Vertical capsule with a glass background (Liquid Glass on iOS 26+, blur material before).
    private static func pill(with buttons: [UIButton]) -> UIView {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect(style: .regular)
        } else {
            effect = UIBlurEffect(style: .systemThinMaterial)
        }
        let pill = UIVisualEffectView(effect: effect)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer.cornerRadius = pillWidth / 2
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        if #unavailable(iOS 26.0) {
            pill.layer.borderWidth = 1 / UIScreen.main.scale
            pill.layer.borderColor = UIColor.separator.cgColor
        }

        let column = UIStackView(arrangedSubviews: buttons)
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(column)
        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: pillWidth),
            column.topAnchor.constraint(equalTo: pill.contentView.topAnchor, constant: 4),
            column.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor, constant: -4),
            column.centerXAnchor.constraint(equalTo: pill.contentView.centerXAnchor),
        ])
        return pill
    }

    /// With the default 61 pt strip and 14 pt right margin this leaves a small gap to the dashed safe area line.
    private static let pillWidth: CGFloat = 44

    static func button(image: UIImage?, label: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = image
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: pillWidth).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }
}

/// Wi‑Fi glyph inside a ring: solid arc over the top, dotted arc along the bottom.
final class WifiRingView: UIView {
    private let icon = UIImageView(image: UIImage(systemName: "wifi"))
    private let solid = CAShapeLayer()
    private let dotted = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.contentMode = .center
        addSubview(icon)
        for ring in [solid, dotted] {
            ring.fillColor = UIColor.clear.cgColor
            ring.lineWidth = 2
            layer.addSublayer(ring)
        }
        solid.lineCap = .round
        dotted.lineCap = .round
        dotted.lineDashPattern = [0, 5]
        isAccessibilityElement = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: WifiRingView, _: UITraitCollection) in
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = bounds.offsetBy(dx: 0, dy: -1)
        icon.tintColor = .label
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 1.5
        // UIKit angles: 0 = right, clockwise. Solid from lower-left over the top to lower-right.
        solid.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: .pi * 0.8, endAngle: .pi * 0.2 + 2 * .pi,
                                  clockwise: true).cgPath
        dotted.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: .pi * 0.2 + 0.25, endAngle: .pi * 0.8 - 0.25,
                                   clockwise: true).cgPath
        let color = UIColor.label.resolvedColor(with: traitCollection).cgColor
        solid.strokeColor = color
        dotted.strokeColor = color
    }
}
