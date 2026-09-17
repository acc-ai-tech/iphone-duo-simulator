import AVKit
import DuoPreviewKit
import UIKit

// MARK: - Chat (keyboard, text input, scroll to bottom)

final class ChatViewController: UIViewController, UITableViewDataSource, UITextFieldDelegate {
    private let tableView = UITableView()
    private let inputBar = UIView()
    private let textField = UITextField()
    private var messages: [(text: String, mine: Bool)] = (0..<60).map { (Sample.sentence($0 * 3, words: 3 + $0 % 14), $0 % 3 == 0) }

    override func viewDidLoad() {
        super.viewDidLoad()
        DuoPreview.track(self)
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.register(BubbleCell.self, forCellReuseIdentifier: "bubble")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        inputBar.backgroundColor = .secondarySystemBackground
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        textField.placeholder = "Message"
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .send
        textField.delegate = self
        let send = UIButton(type: .system, primaryAction: UIAction(title: "Send") { [weak self] _ in self?.send() })
        let stack = UIStackView(arrangedSubviews: [textField, send])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(stack)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: inputBar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: inputBar.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: inputBar.layoutMarginsGuide.trailingAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.scrollToBottom(animated: false) }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: animated)
    }

    private func send() {
        guard let text = textField.text, !text.isEmpty else { return }
        messages.append((text, true))
        textField.text = ""
        tableView.insertRows(at: [IndexPath(row: messages.count - 1, section: 0)], with: .automatic)
        scrollToBottom(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return false
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bubble", for: indexPath) as! BubbleCell
        let message = messages[indexPath.row]
        cell.configure(text: message.text, mine: message.mine)
        return cell
    }
}

final class BubbleCell: UITableViewCell {
    private let bubble = UIView()
    private let label = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        bubble.layer.cornerRadius = 16
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)
        bubble.addSubview(label)
        leading = bubble.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        trailing = bubble.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.72),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, mine: Bool) {
        label.text = text
        bubble.backgroundColor = mine ? .systemBlue : .secondarySystemBackground
        label.textColor = mine ? .white : .label
        leading.isActive = !mine
        trailing.isActive = mine
    }
}

// MARK: - Form

final class FormViewController: UITableViewController {
    private let sections: [(String, [String])] = [
        ("Account", ["Name", "Email", "Phone"]),
        ("Preferences", ["Notifications", "Dark mode", "Autoplay video", "Haptics", "Low data mode"]),
        ("Appearance", ["Text size", "Accent color"]),
        ("About", (1...12).map { "Legal item \($0)" }),
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        DuoPreview.track(self)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 ? Sample.sentence(99, words: 18) : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let title = sections[indexPath.section].1[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = title
        cell.accessoryView = nil
        cell.accessoryType = .none
        switch indexPath.section {
        case 0:
            let field = UITextField(frame: CGRect(x: 0, y: 0, width: 220, height: 32))
            field.placeholder = title
            field.textAlignment = .right
            cell.accessoryView = field
        case 1:
            let toggle = UISwitch()
            toggle.isOn = indexPath.row % 2 == 0
            cell.accessoryView = toggle
        case 2:
            if indexPath.row == 0 {
                let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 200, height: 32))
                slider.value = 0.4
                cell.accessoryView = slider
            } else {
                let segmented = UISegmentedControl(items: ["Blue", "Pink", "Green"])
                segmented.selectedSegmentIndex = 0
                cell.accessoryView = segmented
            }
        default:
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - Video (posture-aware)

/// halfOpen with a horizontal hinge: video above the hinge, controls below. Otherwise video fills the width.
final class VideoViewController: UIViewController {
    private let playerController = AVPlayerViewController()
    private let controls = UIStackView()
    private let postureLabel = UILabel()
    private let hingeBar = UIView()
    private var subscription: DuoSubscription?

    override func viewDidLoad() {
        super.viewDidLoad()
        DuoPreview.track(self)
        view.backgroundColor = .systemBackground

        if let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8") {
            playerController.player = AVPlayer(url: url)
        }
        playerController.view.backgroundColor = .black
        addChild(playerController)
        view.addSubview(playerController.view)
        playerController.didMove(toParent: self)

        hingeBar.backgroundColor = .systemOrange.withAlphaComponent(0.5)
        view.addSubview(hingeBar)

        postureLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        postureLabel.numberOfLines = 0
        postureLabel.textAlignment = .center
        controls.axis = .vertical
        controls.spacing = 12
        controls.alignment = .center
        let buttons = UIStackView(arrangedSubviews: [
            UIButton(configuration: .filled(), primaryAction: UIAction(title: "Play", image: UIImage(systemName: "play.fill")) { [weak self] _ in
                self?.playerController.player?.play()
            }),
            UIButton(configuration: .gray(), primaryAction: UIAction(title: "Pause", image: UIImage(systemName: "pause.fill")) { [weak self] _ in
                self?.playerController.player?.pause()
            }),
        ])
        buttons.spacing = 12
        let scrubber = UISlider()
        scrubber.widthAnchor.constraint(equalToConstant: 280).isActive = true
        controls.addArrangedSubview(postureLabel)
        controls.addArrangedSubview(buttons)
        controls.addArrangedSubview(scrubber)
        view.addSubview(controls)

        // Trait-based updates (preferred) …
        registerForTraitChanges([DuoPostureTrait.self, DuoHingeTrait.self]) { (self: Self, _: UITraitCollection) in
            self.view.setNeedsLayout()
        }
        // … and the callback API.
        subscription = DuoPreview.onStateChange { old, new in
            print("[Example] Duo state \(old.hingeAngle)° → \(new.hingeAngle)° posture=\(new.posture)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let posture = traitCollection.duoPosture
        let hinge = traitCollection.duoHinge
        let bounds = view.bounds
        let safe = view.safeAreaLayoutGuide.layoutFrame

        postureLabel.text = "posture: \(posture.rawValue)  angle: \(Int(hinge.angle))°\n"
            + "hingeRect: \(hinge.rect.isNull ? "null" : "\(hinge.rect.integral)")"

        if posture == .halfOpen, !hinge.rect.isNull, hinge.rect.width > hinge.rect.height {
            // Horizontal hinge: video on top, controls at the bottom (tabletop layout).
            playerController.view.frame = CGRect(x: 0, y: safe.minY, width: bounds.width, height: hinge.rect.minY - safe.minY)
            hingeBar.frame = hinge.rect
            controls.frame = CGRect(x: 0, y: hinge.rect.maxY, width: bounds.width, height: bounds.height - hinge.rect.maxY)
        } else if posture == .halfOpen, !hinge.rect.isNull {
            // Vertical hinge: video left, controls right (book layout).
            playerController.view.frame = CGRect(x: 0, y: safe.minY, width: hinge.rect.minX, height: safe.height)
            hingeBar.frame = hinge.rect
            controls.frame = CGRect(x: hinge.rect.maxX, y: safe.minY, width: bounds.width - hinge.rect.maxX, height: safe.height)
        } else {
            let height = min(bounds.width * 9 / 16, safe.height * 0.6)
            playerController.view.frame = CGRect(x: 0, y: safe.minY, width: bounds.width, height: height)
            hingeBar.frame = hinge.rect.isNull ? .zero : hinge.rect
            controls.frame = CGRect(x: 0, y: safe.minY + height, width: bounds.width, height: safe.maxY - safe.minY - height)
        }
        hingeBar.isHidden = hinge.rect.isNull
    }
}

// MARK: - Modals

final class ModalsViewController: UITableViewController {
    private let actions: [(String, (ModalsViewController) -> Void)] = [
        ("Alert", { vc in
            let alert = UIAlertController(title: "Alert", message: Sample.sentence(5, words: 12), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            vc.present(alert, animated: true)
        }),
        ("Action sheet", { vc in
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            ["Share", "Copy", "Delete"].forEach { sheet.addAction(UIAlertAction(title: $0, style: .default)) }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = vc.tableView
            sheet.popoverPresentationController?.sourceRect = CGRect(x: vc.tableView.bounds.midX, y: 80, width: 1, height: 1)
            vc.present(sheet, animated: true)
        }),
        ("Page sheet", { $0.presentSample(style: .pageSheet) }),
        ("Form sheet", { $0.presentSample(style: .formSheet) }),
        ("Sheet with detents", { vc in
            let nav = UINavigationController(rootViewController: DeepNavigationViewController(level: 1))
            nav.sheetPresentationController?.detents = [.medium(), .large()]
            nav.sheetPresentationController?.prefersGrabberVisible = true
            vc.present(nav, animated: true)
        }),
        ("Full screen", { $0.presentSample(style: .fullScreen) }),
        ("Over current context (stays inside Duo)", { $0.presentSample(style: .overCurrentContext) }),
        ("Current context (stays inside Duo)", { $0.presentSample(style: .currentContext) }),
        ("Popover", { vc in
            let content = ArticleViewController()
            content.modalPresentationStyle = .popover
            content.preferredContentSize = CGSize(width: 320, height: 400)
            content.popoverPresentationController?.sourceView = vc.tableView
            content.popoverPresentationController?.sourceRect = CGRect(x: 40, y: 40, width: 1, height: 1)
            vc.present(content, animated: true)
        }),
        ("Activity view", { vc in
            let activity = UIActivityViewController(activityItems: ["Hello from Duo"], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = vc.view
            vc.present(activity, animated: true)
        }),
        ("Date picker", { vc in
            let picker = UIViewController()
            let datePicker = UIDatePicker()
            datePicker.preferredDatePickerStyle = .inline
            picker.view = datePicker
            picker.view.backgroundColor = .systemBackground
            picker.sheetPresentationController?.detents = [.medium()]
            vc.present(picker, animated: true)
        }),
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        DuoPreview.track(self)
        definesPresentationContext = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    /// `-present alert|actionSheet|pageSheet|formSheet|detents|fullScreen|overCurrentContext|currentContext|popover`
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let keys = ["alert", "actionSheet", "pageSheet", "formSheet", "detents", "fullScreen",
                    "overCurrentContext", "currentContext", "popover", "activity", "datePicker"]
        guard presentedViewController == nil, let name = UserDefaults.standard.string(forKey: "present"),
              let index = keys.firstIndex(of: name) else { return }
        UserDefaults.standard.removeObject(forKey: "present")
        actions[index].1(self)
    }

    fileprivate func presentSample(style: UIModalPresentationStyle) {
        let content = DeepNavigationViewController(level: 1)
        content.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        let nav = UINavigationController(rootViewController: content)
        nav.modalPresentationStyle = style
        present(nav, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { actions.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Known limitation: alerts, sheets and popovers are positioned by UIKit relative to the iPad window and can extend outside the Duo area. currentContext/overCurrentContext stay inside."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = actions[indexPath.row].0
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        actions[indexPath.row].1(self)
    }
}

// MARK: - Posture debug

/// Shows every value the API exposes and draws `hingeRect`.
final class PostureDebugViewController: UIViewController {
    private let label = UILabel()
    private let hingeOverlay = UIView()
    private let leftPane = UIView()
    private let rightPane = UIView()
    private var streamTask: Task<Void, Never>?
    private var streamCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        DuoPreview.track(self)
        view.backgroundColor = .systemBackground
        leftPane.backgroundColor = .systemBlue.withAlphaComponent(0.15)
        rightPane.backgroundColor = .systemGreen.withAlphaComponent(0.15)
        hingeOverlay.backgroundColor = .systemRed.withAlphaComponent(0.6)
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        [leftPane, rightPane, hingeOverlay, label].forEach(view.addSubview)

        registerForTraitChanges([DuoPostureTrait.self, DuoHingeTrait.self,
                                 UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.view.setNeedsLayout()
        }
        streamTask = Task { [weak self] in
            for await _ in DuoPreview.stateStream {
                guard let self else { return }
                self.streamCount += 1
                self.view.setNeedsLayout()
            }
        }
    }

    deinit {
        streamTask?.cancel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let traits = traitCollection
        let hinge = traits.duoHinge
        let bounds = view.bounds
        let safe = view.safeAreaLayoutGuide.layoutFrame

        if hinge.rect.isNull {
            leftPane.frame = bounds
            rightPane.frame = .zero
        } else if hinge.rect.height > hinge.rect.width {
            leftPane.frame = CGRect(x: 0, y: 0, width: hinge.rect.minX, height: bounds.height)
            rightPane.frame = CGRect(x: hinge.rect.maxX, y: 0, width: bounds.width - hinge.rect.maxX, height: bounds.height)
        } else {
            leftPane.frame = CGRect(x: 0, y: 0, width: bounds.width, height: hinge.rect.minY)
            rightPane.frame = CGRect(x: 0, y: hinge.rect.maxY, width: bounds.width, height: bounds.height - hinge.rect.maxY)
        }
        hingeOverlay.frame = hinge.rect.isNull ? .zero : hinge.rect

        label.text = """
        view.bounds      \(Int(bounds.width))×\(Int(bounds.height))
        safeArea         \(safe.integral)
        sizeClass        h:\(name(traits.horizontalSizeClass)) v:\(name(traits.verticalSizeClass))
        trait posture    \(traits.duoPosture.rawValue)
        trait angle      \(Int(hinge.angle))°
        trait hingeRect  \(hinge.rect.isNull ? "null" : "\(hinge.rect.integral)")
        API posture      \(DuoPreview.posture.rawValue)
        API angle        \(Int(DuoPreview.hingeAngle))°
        API hingeRect    \(DuoPreview.hingeRect.isNull ? "null" : "\(DuoPreview.hingeRect.integral)")
        API contentSize  \(DuoPreview.contentSize)
        stream events    \(streamCount)
        """
        let target = leftPane.frame.width > 0 && leftPane.frame.height > 0 ? leftPane.frame : bounds
        let size = label.sizeThatFits(CGSize(width: target.width - 32, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: target.minX + 16, y: max(safe.minY, target.minY) + 16, width: target.width - 32, height: size.height)
    }

    private func name(_ sizeClass: UIUserInterfaceSizeClass) -> String {
        switch sizeClass {
        case .compact: "compact"
        case .regular: "regular"
        default: "unspecified"
        }
    }
}
