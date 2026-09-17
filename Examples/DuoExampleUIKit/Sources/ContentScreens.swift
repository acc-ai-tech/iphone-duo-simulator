import UIKit
#if DEBUG
import DuoPreviewKit
#endif

// MARK: - Sample data

enum Sample {
    static let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemMint, .systemTeal,
                                    .systemCyan, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemBrown]
    static let symbols = ["sun.max.fill", "cloud.rain.fill", "leaf.fill", "flame.fill", "bolt.fill", "moon.stars.fill",
                          "car.fill", "airplane", "tram.fill", "bicycle", "figure.run", "music.note", "camera.fill",
                          "gamecontroller.fill", "book.fill", "cup.and.saucer.fill", "fork.knife", "cart.fill"]
    static let words = """
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna \
    aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis \
    aute irure in reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint occaecat cupidatat \
    non proident sunt culpa qui officia deserunt mollit anim id est laborum
    """.split(separator: " ").map(String.init)

    static func sentence(_ seed: Int, words count: Int) -> String {
        var generator = SeededGenerator(seed: UInt64(seed + 1))
        let text = (0..<count).map { _ in words[Int(generator.next() % UInt64(words.count))] }.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    static func color(_ i: Int) -> UIColor { colors[abs(i) % colors.count] }
    static func symbol(_ i: Int) -> String { symbols[abs(i) % symbols.count] }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Feed (compositional grid adapting to width)

final class FeedViewController: UICollectionViewController {
    private let items = Array(0..<120)

    init() {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width
            let columns = max(1, Int(width / 210))
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(230)),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(12)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.contentInsets = .init(top: 12, leading: 16, bottom: 24, trailing: 16)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(64)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            header.pinToVisibleBounds = true
            section.boundarySupplementaryItems = [header]
            return section
        }
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        DuoPreview.track(self)
        #endif
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.register(FeedCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.register(FeedHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(systemItem: .add),
            UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: nil, action: nil),
        ]
        navigationItem.searchController = UISearchController()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        print("[Example] FeedViewController.viewWillTransition(to: \(size))")
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! FeedCell
        cell.configure(index: items[indexPath.item])
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                                 at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! FeedHeader
        header.label.text = "\(items.count) items · width \(Int(collectionView.bounds.width)) pt"
        return header
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let detail = ArticleViewController()
        detail.title = "Item \(indexPath.item)"
        navigationController?.pushViewController(detail, animated: true)
    }
}

final class FeedHeader: UICollectionReusableView {
    let label = UILabel()
    private let segmented = UISegmentedControl(items: ["All", "Popular", "New", "Saved"])

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground.withAlphaComponent(0.95)
        segmented.selectedSegmentIndex = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [segmented, label])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

final class FeedCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badge = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 14
        contentView.clipsToBounds = true

        imageView.contentMode = .center
        imageView.tintColor = .white
        imageView.preferredSymbolConfiguration = .init(pointSize: 44, weight: .semibold)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .black.withAlphaComponent(0.35)
        badge.layer.cornerRadius = 8
        badge.clipsToBounds = true
        badge.textAlignment = .center

        for view in [imageView, titleLabel, subtitleLabel, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.58),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            badge.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int) {
        imageView.backgroundColor = Sample.color(index)
        imageView.image = UIImage(systemName: Sample.symbol(index))
        titleLabel.text = "Card #\(index)"
        subtitleLabel.text = Sample.sentence(index, words: 12)
        badge.text = " \(index % 7 + 1)k "
    }
}

// MARK: - Gallery (grid → paging detail)

final class GalleryViewController: UICollectionViewController {
    init() {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width
            let columns = max(3, Int(width / 110))
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(1 / CGFloat(columns))),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(2)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 2
            return section
        }
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        DuoPreview.track(self)
        #endif
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 300 }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = Sample.color(indexPath.item * 5 + indexPath.item / 3)
        cell.backgroundConfiguration = background
        var content = UIListContentConfiguration.cell()
        content.image = UIImage(systemName: Sample.symbol(indexPath.item))
        content.imageProperties.tintColor = .white
        content.text = "\(indexPath.item)"
        content.textProperties.color = .white
        cell.contentConfiguration = content
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        navigationController?.pushViewController(PhotoPagerViewController(start: indexPath.item), animated: true)
    }
}

final class PhotoPagerViewController: UIViewController, UIScrollViewDelegate {
    private let start: Int
    private let scrollView = UIScrollView()
    private var pages: [UIView] = []

    init(start: Int) {
        self.start = start
        super.init(nibName: nil, bundle: nil)
        title = "Photo \(start)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.isPagingEnabled = true
        scrollView.delegate = self
        view.addSubview(scrollView)
        for i in 0..<20 {
            let page = UIImageView(image: UIImage(systemName: Sample.symbol(start + i)))
            page.contentMode = .scaleAspectFit
            page.tintColor = .white
            page.backgroundColor = Sample.color(start + i)
            scrollView.addSubview(page)
            pages.append(page)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let page = Int((scrollView.contentOffset.x / max(scrollView.bounds.width, 1)).rounded())
        scrollView.frame = view.bounds
        for (i, pageView) in pages.enumerated() {
            pageView.frame = CGRect(x: CGFloat(i) * view.bounds.width, y: 0, width: view.bounds.width, height: view.bounds.height)
                .insetBy(dx: 40, dy: 80)
        }
        scrollView.contentSize = CGSize(width: CGFloat(pages.count) * view.bounds.width, height: view.bounds.height)
        // Keep the current page after a size change (classic resize bug).
        scrollView.contentOffset.x = CGFloat(page) * view.bounds.width
    }
}

// MARK: - Article (long text, readable width)

final class ArticleViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        DuoPreview.track(self)
        #endif
        view.backgroundColor = .systemBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
        ])

        let hero = UIImageView(image: UIImage(systemName: "mountain.2.fill"))
        hero.contentMode = .scaleAspectFit
        hero.tintColor = .white
        hero.backgroundColor = .systemTeal
        hero.layer.cornerRadius = 16
        hero.clipsToBounds = true
        hero.heightAnchor.constraint(equalTo: hero.widthAnchor, multiplier: 0.5).isActive = true
        stack.addArrangedSubview(hero)

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.numberOfLines = 0
        title.text = "Folding screens and adaptive layouts"
        stack.addArrangedSubview(title)

        for i in 0..<30 {
            if i % 6 == 3 {
                let quote = UILabel()
                quote.font = .italicSystemFont(ofSize: 22)
                quote.textColor = .systemIndigo
                quote.numberOfLines = 0
                quote.text = "“" + Sample.sentence(i * 31, words: 14) + "”"
                stack.addArrangedSubview(quote)
            }
            let paragraph = UILabel()
            paragraph.font = .preferredFont(forTextStyle: .body)
            paragraph.adjustsFontForContentSizeCategory = true
            paragraph.numberOfLines = 0
            paragraph.text = (0..<5).map { Sample.sentence(i * 10 + $0, words: 10 + ($0 * 3) % 9) }.joined(separator: " ")
            stack.addArrangedSubview(paragraph)
        }
    }
}

// MARK: - Deep navigation

final class DeepNavigationViewController: UITableViewController {
    private let level: Int

    init(level: Int) {
        self.level = level
        super.init(style: .insetGrouped)
        title = "Level \(level)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        DuoPreview.track(self)
        #endif
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.prompt = level > 1 ? "Push depth \(level)" : nil
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : 25 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Navigation", "Rows", "More rows"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = "Push level \(level + 1)"
            content.image = UIImage(systemName: "arrow.right.circle.fill")
            cell.accessoryType = .disclosureIndicator
        } else {
            content.text = "Row \(indexPath.section).\(indexPath.row) — " + Sample.sentence(indexPath.row + level, words: 4)
            content.secondaryText = Sample.sentence(indexPath.row * 7, words: 8)
            content.image = UIImage(systemName: Sample.symbol(indexPath.row))
            content.imageProperties.tintColor = Sample.color(indexPath.row)
            cell.accessoryType = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        navigationController?.pushViewController(DeepNavigationViewController(level: level + 1), animated: true)
    }
}
