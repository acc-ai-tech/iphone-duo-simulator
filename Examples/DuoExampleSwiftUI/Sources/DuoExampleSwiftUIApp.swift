import AVKit
import DuoPreviewKit
import SwiftUI

@main
struct DuoExampleSwiftUIApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // DuoHinge.rect is in content (root view) coordinates.
                .coordinateSpace(.named(DuoContent.space))
                .duoPreviewHost()
        }
    }
}

enum DuoContent {
    static let space = "duoContent"
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case library, grid, reader, compose, player, settings, posture

    var id: Self { self }

    var title: String {
        switch self {
        case .library: "Library"
        case .grid: "Grid"
        case .reader: "Reader"
        case .compose: "Compose"
        case .player: "Player (posture)"
        case .settings: "Settings"
        case .posture: "Posture Debug"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .grid: "square.grid.3x3"
        case .reader: "text.book.closed"
        case .compose: "square.and.pencil"
        case .player: "play.tv"
        case .settings: "gearshape"
        case .posture: "rectangle.split.2x1"
        }
    }
}

struct RootView: View {
    @State private var section: AppSection? = AppSection(rawValue: UserDefaults.standard.string(forKey: "screen") ?? "") ?? .library
    @State private var visibility: NavigationSplitViewVisibility = .automatic
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.duoPosture) private var posture
    @Environment(\.duoHinge) private var hinge

    /// Half-open with a vertical hinge: sidebar ends exactly at the hinge (50/50).
    private var hingeSidebarWidth: CGFloat? {
        guard posture == .halfOpen, !hinge.rect.isNull, hinge.rect.height > hinge.rect.width else { return nil }
        return hinge.rect.minX
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(AppSection.allCases, selection: $section) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.symbol)
                }
            }
            .navigationTitle("Duo SwiftUI")
            .navigationSplitViewColumnWidth(min: hingeSidebarWidth ?? 180, ideal: hingeSidebarWidth ?? 320,
                                            max: hingeSidebarWidth ?? 400)
        } detail: {
            NavigationStack {
                switch section ?? .library {
                case .library: LibraryView()
                case .grid: GridView()
                case .reader: ReaderView()
                case .compose: ComposeView()
                case .player: PlayerView()
                case .settings: SettingsView()
                case .posture: PostureDebugView()
                }
            }
        }
    }
}

// MARK: - Sample data

struct Item: Identifiable, Hashable {
    let id: Int
    var title: String { "Item \(id)" }
    var subtitle: String { Lorem.sentence(id, words: 10) }
    var color: Color { Lorem.colors[id % Lorem.colors.count] }
    var symbol: String { Lorem.symbols[id % Lorem.symbols.count] }
}

enum Lorem {
    static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown]
    static let symbols = ["sun.max.fill", "cloud.rain.fill", "leaf.fill", "flame.fill", "bolt.fill", "moon.stars.fill",
                          "car.fill", "airplane", "tram.fill", "bicycle", "music.note", "camera.fill", "book.fill"]
    static let words = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat"
        .split(separator: " ").map(String.init)

    static func sentence(_ seed: Int, words count: Int) -> String {
        var state = UInt64(seed + 7) &* 0x9E37_79B9_7F4A_7C15
        let text = (0..<count).map { _ -> String in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return words[Int(state % UInt64(words.count))]
        }.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }
}

// MARK: - Library (list → detail)

struct LibraryView: View {
    @State private var search = ""
    private let items = (0..<200).map(Item.init)

    var body: some View {
        List {
            ForEach(items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(item.color, in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading) {
                            Text(item.title).font(.headline)
                            Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Library")
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
        .toolbar {
            ToolbarItem { Button("Add", systemImage: "plus") {} }
        }
    }
}

struct ItemDetailView: View {
    let item: Item
    @State private var showSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: item.symbol)
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(item.color.gradient, in: .rect(cornerRadius: 20))
                Text(item.title).font(.largeTitle.bold())
                ForEach(0..<8) { i in
                    Text(Lorem.sentence(item.id * 13 + i, words: 40))
                }
                Button("Show sheet") { showSheet = true }.buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                List(0..<30) { Text("Row \($0)") }
                    .navigationTitle("Sheet")
                    .toolbar { Button("Done") { showSheet = false } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Grid

struct GridView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach((0..<150).map(Item.init)) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(item.color.gradient, in: .rect(cornerRadius: 14))
                        Text(item.title).font(.headline)
                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Grid")
    }
}

// MARK: - Reader (two columns when a vertical hinge crosses the content)

struct ReaderView: View {
    @Environment(\.duoHinge) private var hinge
    @Environment(\.duoPosture) private var posture

    var body: some View {
        GeometryReader { proxy in
            let hingeX = hinge.rect.minX - proxy.frame(in: .named(DuoContent.space)).minX
            if !hinge.rect.isNull, hinge.rect.height > hinge.rect.width, posture != .closed, hingeX > 0 {
                // Book mode: one page on each side of the hinge.
                HStack(spacing: 0) {
                    page(0).frame(width: hingeX)
                    Color.clear.frame(width: hinge.rect.width)
                    page(1).frame(width: max(proxy.size.width - hingeX - hinge.rect.width, 0))
                }
            } else {
                page(0)
            }
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func page(_ index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chapter \(index + 1)").font(.title.bold())
                ForEach(0..<20) { i in
                    Text(Lorem.sentence(index * 100 + i, words: 30 + i % 20)).font(.body)
                }
            }
            .padding()
        }
    }
}

// MARK: - Compose (keyboard)

struct ComposeView: View {
    @State private var subject = ""
    @State private var text = Lorem.sentence(4, words: 80)
    @State private var messages = (0..<30).map { Lorem.sentence($0, words: 3 + $0 % 12) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                List(Array(messages.enumerated()), id: \.offset) { index, message in
                    Text(message).id(index)
                }
                .onAppear { reader.scrollTo(messages.count - 1, anchor: .bottom) }
            }
            Divider()
            VStack(spacing: 8) {
                TextField("Subject", text: $subject).textFieldStyle(.roundedBorder)
                TextEditor(text: $text).frame(height: 100).border(.quaternary)
                Button("Send") {
                    messages.append(subject.isEmpty ? text : subject)
                    subject = ""
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Compose")
    }
}

// MARK: - Player (tabletop layout in halfOpen)

struct PlayerView: View {
    @Environment(\.duoPosture) private var posture
    @Environment(\.duoHinge) private var hinge
    @State private var player = AVPlayer(url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8")!)
    @State private var progress = 0.3

    var body: some View {
        GeometryReader { proxy in
            let global = proxy.frame(in: .named(DuoContent.space))
            if posture == .halfOpen, !hinge.rect.isNull, hinge.rect.width > hinge.rect.height {
                // Horizontal hinge: video above, controls below (hinge rect is in content coordinates).
                let hingeTop = max(hinge.rect.minY - global.minY, 0)
                VStack(spacing: 0) {
                    VideoPlayer(player: player).frame(height: hingeTop)
                    Color.orange.opacity(0.4).frame(height: hinge.rect.height)
                    controls.frame(maxHeight: .infinity)
                }
            } else if posture == .halfOpen, !hinge.rect.isNull {
                let hingeLeft = max(hinge.rect.minX - global.minX, 0)
                HStack(spacing: 0) {
                    VideoPlayer(player: player).frame(width: hingeLeft)
                    Color.orange.opacity(0.4).frame(width: hinge.rect.width)
                    controls.frame(maxWidth: .infinity)
                }
            } else {
                VStack {
                    VideoPlayer(player: player).aspectRatio(16 / 9, contentMode: .fit)
                    controls
                    Spacer()
                }
            }
        }
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            Text("posture: \(posture.rawValue) · \(Int(hinge.angle))°").font(.system(.body, design: .monospaced))
            HStack(spacing: 24) {
                Button("Back", systemImage: "gobackward.15") {}
                Button("Play", systemImage: "play.fill") { player.play() }
                Button("Pause", systemImage: "pause.fill") { player.pause() }
                Button("Forward", systemImage: "goforward.15") {}
            }
            .labelStyle(.iconOnly)
            .font(.title)
            Slider(value: $progress).padding(.horizontal, 40)
        }
        .padding()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var toggles = Array(repeating: true, count: 8)
    @State private var volume = 0.5
    @State private var name = ""
    @State private var date = Date()
    @State private var choice = 1

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                DatePicker("Birthday", selection: $date, displayedComponents: .date)
                Picker("Plan", selection: $choice) {
                    Text("Free").tag(0)
                    Text("Pro").tag(1)
                    Text("Team").tag(2)
                }
            }
            Section("Toggles") {
                ForEach(toggles.indices, id: \.self) { i in
                    Toggle("Option \(i + 1)", isOn: $toggles[i])
                }
            }
            Section("Audio") {
                Slider(value: $volume)
                Stepper("Volume \(Int(volume * 100))", value: $volume, in: 0...1, step: 0.1)
            }
            Section {
                ForEach(0..<15) { NavigationLink("Legal \($0)") { ReaderView() } }
            } footer: {
                Text(Lorem.sentence(9, words: 30))
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Posture debug

struct PostureDebugView: View {
    @Environment(\.duoPosture) private var posture
    @Environment(\.duoHinge) private var hinge
    @Environment(\.horizontalSizeClass) private var h
    @Environment(\.verticalSizeClass) private var v
    @State private var streamEvents = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.blue.opacity(0.08)
                if !hinge.rect.isNull {
                    let origin = proxy.frame(in: .named(DuoContent.space)).origin
                    Rectangle()
                        .fill(.red.opacity(0.6))
                        .frame(width: hinge.rect.width, height: hinge.rect.height)
                        .offset(x: hinge.rect.minX - origin.x, y: hinge.rect.minY - origin.y)
                }
                VStack(alignment: .leading, spacing: 4) {
                    row("size", "\(Int(proxy.size.width))×\(Int(proxy.size.height))")
                    row("sizeClass", "h:\(name(h)) v:\(name(v))")
                    row("env posture", posture.rawValue)
                    row("env angle", "\(Int(hinge.angle))°")
                    row("env hingeRect", hinge.rect.isNull ? "null" : "\(hinge.rect.integral)")
                    row("API posture", DuoPreview.posture.rawValue)
                    row("API contentSize", "\(DuoPreview.contentSize)")
                    row("stream events", "\(streamEvents)")
                }
                .font(.system(.body, design: .monospaced))
                .padding()
            }
        }
        .navigationTitle("Posture")
        .task {
            for await _ in DuoPreview.stateStream { streamEvents += 1 }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
            Text(value)
        }
    }

    private func name(_ sizeClass: UserInterfaceSizeClass?) -> String {
        switch sizeClass {
        case .compact: "compact"
        case .regular: "regular"
        default: "nil"
        }
    }
}
