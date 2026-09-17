import UIKit
import os

/// Parameters of ``DuoPreview/runStressTest(_:)``.
public struct DuoStressTestConfiguration: Sendable {
    /// Number of passes through `sequence`.
    public var cycles: Int
    /// State tokens: preset id with optional `@angle`, e.g. `inner.landscape@90`.
    public var sequence: [String]
    public var animation: DuoAnimation
    /// Pause after each transition before the screenshot, seconds.
    public var delay: TimeInterval
    /// Channel delta (0–255) above which a pixel counts as changed.
    public var channelThreshold: Int

    public init(cycles: Int, sequence: [String], animation: DuoAnimation, delay: TimeInterval, channelThreshold: Int) {
        self.cycles = cycles
        self.sequence = sequence
        self.animation = animation
        self.delay = delay
        self.channelThreshold = channelThreshold
    }

    /// Defaults from `tools` in JSON.
    public init(config: DuoConfiguration = .current, animation: DuoAnimation = .realistic) {
        self.init(cycles: config.tools.stressCycles, sequence: config.tools.stressSequence, animation: animation,
                  delay: config.tools.stressDelay, channelThreshold: config.tools.diffChannelThreshold)
    }
}

/// Counts `viewDidLoad` (via ``DuoPreview/track(_:)``) and `deinit` of tracked controllers. No swizzling.
final class LifecycleTracker: Sendable {
    static let shared = LifecycleTracker()

    struct Counters: Codable, Sendable {
        var loads = 0
        var deinits = 0
    }

    private let counters = OSAllocatedUnfairLock<[String: Counters]>(initialState: [:])
    nonisolated(unsafe) private static let sentinelKey = malloc(1)!

    private final class Sentinel: NSObject {
        let typeName: String
        let tracker: LifecycleTracker
        init(typeName: String, tracker: LifecycleTracker) {
            self.typeName = typeName
            self.tracker = tracker
        }
        deinit {
            let name = typeName
            tracker.counters.withLock { $0[name, default: Counters()].deinits += 1 }
        }
    }

    @MainActor
    func track(_ viewController: UIViewController) {
        let name = String(reflecting: type(of: viewController))
        counters.withLock { $0[name, default: Counters()].loads += 1 }
        guard objc_getAssociatedObject(viewController, Self.sentinelKey) == nil else { return }
        let sentinel = Sentinel(typeName: name, tracker: self)
        objc_setAssociatedObject(viewController, Self.sentinelKey, sentinel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func snapshot() -> [String: Counters] {
        counters.withLock { $0 }
    }
}

@MainActor
enum StressTest {
    struct StepReport: Codable {
        var cycle: Int
        var step: Int
        var state: String
        var contentSize: [Double]
        var changedPixels: Int
        var totalPixels: Int
        var changedFraction: Double
        var diffImage: String?
    }

    struct Report: Codable {
        var startedAt: String
        var finishedAt: String
        var cycles: Int
        var sequence: [String]
        var animation: String
        var delay: Double
        var channelThreshold: Int
        var transitions: Int
        var stepsWithDifferences: Int
        var maxChangedFraction: Double
        var steps: [StepReport]
        var lifecycle: [String: LifecycleTracker.Counters]
        var lifecycleBefore: [String: LifecycleTracker.Counters]
    }

    static func run(_ configuration: DuoStressTestConfiguration) async -> URL? {
        let runtime = DuoRuntime.shared
        guard let host = runtime.host else { return nil }
        let config = runtime.config
        let original = runtime.state
        let started = ISO8601DateFormatter().string(from: Date())
        let lifecycleBefore = LifecycleTracker.shared.snapshot()
        let transitionsBefore = runtime.transitionCount
        duoPrint("stress test: \(configuration.cycles) cycles × \(configuration.sequence)")

        do {
            let directory = try Screenshotter.makeOutputDirectory("stress-\(Screenshotter.timestamp())")
            var references: [Int: UIImage] = [:]
            var steps: [StepReport] = []

            for cycle in 0..<max(configuration.cycles, 1) {
                for (index, token) in configuration.sequence.enumerated() {
                    guard let state = DuoState.parse(token, in: config) else {
                        duoPrint("stress test: unknown state token \(token)")
                        continue
                    }
                    await DuoPreview.transition(to: state, animation: configuration.animation)
                    try? await Task.sleep(for: .seconds(configuration.delay))

                    let ignored = runtime.ignoredViews.allObjects
                        .filter { $0.window != nil && $0.isDescendant(of: host.contentContainer) }
                        .map { $0.convert($0.bounds, to: host.contentContainer) }
                    let image = ImageDiff.masking(Screenshotter.captureContent(host: host), rects: ignored)
                    let size = state.contentSize(in: config)
                    var report = StepReport(cycle: cycle, step: index, state: token,
                                            contentSize: [size.width, size.height],
                                            changedPixels: 0, totalPixels: 0, changedFraction: 0, diffImage: nil)

                    if let reference = references[index] {
                        let diff = ImageDiff.compare(reference, image, threshold: configuration.channelThreshold)
                        report.changedPixels = diff.changedPixels
                        report.totalPixels = diff.totalPixels
                        report.changedFraction = diff.changedFraction
                        if let highlight = diff.highlight {
                            let name = "diff-c\(cycle)-\(Screenshotter.fileName(index: index, token: token))"
                            try highlight.pngData()?.write(to: directory.appendingPathComponent(name))
                            try image.pngData()?.write(to: directory.appendingPathComponent("actual-c\(cycle)-\(Screenshotter.fileName(index: index, token: token))"))
                            report.diffImage = name
                        }
                    } else {
                        references[index] = image
                        try image.pngData()?.write(to: directory.appendingPathComponent("reference-\(Screenshotter.fileName(index: index, token: token))"))
                    }
                    steps.append(report)
                }
            }

            await DuoPreview.transition(to: original, animation: .none)

            let compared = steps.filter { $0.cycle > 0 }
            let report = Report(
                startedAt: started,
                finishedAt: ISO8601DateFormatter().string(from: Date()),
                cycles: configuration.cycles,
                sequence: configuration.sequence,
                animation: configuration.animation.kind.rawValue,
                delay: configuration.delay,
                channelThreshold: configuration.channelThreshold,
                transitions: runtime.transitionCount - transitionsBefore,
                stepsWithDifferences: compared.filter { $0.changedPixels > 0 }.count,
                maxChangedFraction: compared.map(\.changedFraction).max() ?? 0,
                steps: steps,
                lifecycle: LifecycleTracker.shared.snapshot(),
                lifecycleBefore: lifecycleBefore
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = directory.appendingPathComponent("report.json")
            try encoder.encode(report).write(to: url)
            duoPrint("stress test done: \(report.stepsWithDifferences)/\(compared.count) steps differ, "
                + "max \(String(format: "%.4f", report.maxChangedFraction)). Report: \(url.path)")
            return url
        } catch {
            duoPrint("stress test failed: \(error)")
            await DuoPreview.transition(to: original, animation: .none)
            return nil
        }
    }
}
