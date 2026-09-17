import DuoPreviewKit
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootSplitViewController(initial: UserDefaults.standard.string(forKey: "screen").flatMap(Screen.init) ?? .feed)
        #if DEBUG
        // `-duoPresets /path/to/presets.json` replaces the bundled presets.
        if let path = UserDefaults.standard.string(forKey: "duoPresets") {
            do { try DuoPreview.configure(presetsURL: URL(fileURLWithPath: path)) } catch { print("[Example] presets: \(error)") }
        }
        // Install before makeKeyAndVisible so the original root does not start appearing at iPad size.
        DuoPreview.install(in: window)
        #endif
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// Sidebar + detail. Collapses to a navigation stack in compact width (outer screen, split presets).
final class RootSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    init(initial: Screen) {
        super.init(style: .doubleColumn)
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        presentsWithGesture = false
        delegate = self

        let sidebar = SidebarViewController()
        sidebar.onSelect = { [weak self] screen in self?.show(screen) }
        setViewController(UINavigationController(rootViewController: sidebar), for: .primary)
        setViewController(UINavigationController(rootViewController: initial.makeViewController()), for: .secondary)

        let compactSidebar = SidebarViewController()
        let compactNav = UINavigationController(rootViewController: compactSidebar)
        compactNav.navigationBar.prefersLargeTitles = true
        compactSidebar.onSelect = { [weak compactNav] screen in
            compactNav?.pushViewController(screen.makeViewController(), animated: true)
        }
        if initial != .feed {
            compactNav.pushViewController(initial.makeViewController(), animated: false)
        }
        setViewController(compactNav, for: .compact)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        DuoPreview.track(self)
        #endif
        registerForTraitChanges([DuoPostureTrait.self, DuoHingeTrait.self]) { (self: Self, _: UITraitCollection) in
            self.applyHingeColumns()
        }
        applyHingeColumns()
    }

    /// Half-open with a vertical hinge: sidebar and detail split 50/50 along the hinge.
    private func applyHingeColumns() {
        let hinge = traitCollection.duoHinge
        if traitCollection.duoPosture == .halfOpen, !hinge.rect.isNull, hinge.rect.height > hinge.rect.width {
            minimumPrimaryColumnWidth = hinge.rect.minX
            maximumPrimaryColumnWidth = hinge.rect.minX
            preferredPrimaryColumnWidth = hinge.rect.minX
            preferredSplitBehavior = .tile
        } else {
            minimumPrimaryColumnWidth = UISplitViewController.automaticDimension
            maximumPrimaryColumnWidth = UISplitViewController.automaticDimension
            preferredPrimaryColumnWidth = UISplitViewController.automaticDimension
        }
    }

    private func show(_ screen: Screen) {
        setViewController(UINavigationController(rootViewController: screen.makeViewController()), for: .secondary)
    }

    func splitViewController(_ svc: UISplitViewController,
                             topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column)
        -> UISplitViewController.Column {
        .compact
    }
}

enum Screen: String, CaseIterable {
    case feed, gallery, article, chat, form, video, modals, deepNavigation, posture

    var title: String {
        switch self {
        case .feed: "Feed"
        case .gallery: "Gallery"
        case .article: "Article"
        case .chat: "Chat"
        case .form: "Settings Form"
        case .video: "Video (posture)"
        case .modals: "Modals & Alerts"
        case .deepNavigation: "Deep Navigation"
        case .posture: "Posture Debug"
        }
    }

    var symbol: String {
        switch self {
        case .feed: "square.grid.2x2"
        case .gallery: "photo.on.rectangle"
        case .article: "doc.richtext"
        case .chat: "bubble.left.and.bubble.right"
        case .form: "gearshape"
        case .video: "play.rectangle"
        case .modals: "rectangle.stack"
        case .deepNavigation: "list.number"
        case .posture: "rectangle.split.2x1"
        }
    }

    @MainActor
    func makeViewController() -> UIViewController {
        let vc: UIViewController = switch self {
        case .feed: FeedViewController()
        case .gallery: GalleryViewController()
        case .article: ArticleViewController()
        case .chat: ChatViewController()
        case .form: FormViewController()
        case .video: VideoViewController()
        case .modals: ModalsViewController()
        case .deepNavigation: DeepNavigationViewController(level: 1)
        case .posture: PostureDebugViewController()
        }
        vc.title = title
        return vc
    }
}

final class SidebarViewController: UICollectionViewController {
    var onSelect: ((Screen) -> Void)?
    private var dataSource: UICollectionViewDiffableDataSource<Int, Screen>!

    init() {
        let config = UICollectionLayoutListConfiguration(appearance: .sidebar)
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
        title = "Duo Test"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        DuoPreview.track(self)
        #endif
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Screen> { cell, _, screen in
            var content = cell.defaultContentConfiguration()
            content.text = screen.title
            content.image = UIImage(systemName: screen.symbol)
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, screen in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: screen)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Screen>()
        snapshot.appendSections([0])
        snapshot.appendItems(Screen.allCases)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let screen = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelect?(screen)
        if splitViewController?.isCollapsed == true {
            collectionView.deselectItem(at: indexPath, animated: true)
        }
    }
}
