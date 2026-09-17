import UIKit
import XCTest
@testable import DuoPreviewKit

/// Records `viewWillTransition` calls and exposes traits.
private final class SpyViewController: UIViewController {
    var transitions: [CGSize] = []
    var alongsideRan = 0
    var completionsRan = 0

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        transitions.append(size)
        coordinator.animate(alongsideTransition: { _ in self.alongsideRan += 1 }, completion: { _ in self.completionsRan += 1 })
    }
}

@MainActor
final class HostTests: XCTestCase {
    private var window: UIWindow!
    private var spy: SpyViewController!
    private var navigation: UINavigationController!
    private var runtime: DuoRuntime { .shared }

    override func setUp() async throws {
        DuoPreview.forceEnable()
        runtime.resetForTesting()
        spy = SpyViewController()
        navigation = UINavigationController(rootViewController: spy)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1032, height: 1376))
        window.rootViewController = navigation
        DuoPreview.install(in: window)
        window.isHidden = false
        window.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        runtime.resetForTesting()
    }

    private var host: DuoHostViewController {
        get throws { try XCTUnwrap(window.rootViewController as? DuoHostViewController) }
    }

    private func apply(_ id: String, angle: Double? = nil) async throws {
        var state = try XCTUnwrap(DuoState.preset(id))
        if let angle { state.hingeAngle = angle }
        await DuoPreview.transition(to: state, animation: .none)
        window.layoutIfNeeded()
    }

    func testInstallWrapsRoot() throws {
        XCTAssertTrue(DuoPreview.isInstalled)
        XCTAssertTrue(try host.content === navigation)
        XCTAssertTrue(navigation.parent is DuoHostViewController)
        // Second install is a no-op.
        DuoPreview.install(in: window)
        XCTAssertTrue(try host.content === navigation)
    }

    func testContentGetsExactPresetSizeAndSizeClasses() async throws {
        for preset in runtime.config.presets {
            try await apply(preset.id)
            XCTAssertEqual(navigation.view.bounds.size, preset.size, preset.id)
            XCTAssertEqual(spy.view.bounds.size, preset.size, preset.id)
            let traits = spy.traitCollection
            XCTAssertEqual(traits.horizontalSizeClass, preset.sizeClass.horizontal == .compact ? .compact : .regular, preset.id)
            XCTAssertEqual(traits.verticalSizeClass, preset.sizeClass.vertical == .compact ? .compact : .regular, preset.id)
        }
    }

    func testViewWillTransitionIsCalledWithNewSize() async throws {
        try await apply("inner.landscape")
        spy.transitions.removeAll()
        DuoPreview.fold(animation: .none)
        XCTAssertEqual(spy.transitions.last, CGSize(width: 466, height: 678))
        DuoPreview.unfold(animation: .none)
        XCTAssertEqual(spy.transitions.last, CGSize(width: 890, height: 626))
        XCTAssertEqual(spy.alongsideRan, 2)
        XCTAssertEqual(spy.completionsRan, 2)
    }

    func testAngleOnlyChangeDoesNotTransitionSize() async throws {
        try await apply("inner.landscape")
        spy.transitions.removeAll()
        DuoPreview.setHingeAngle(90, animated: false)
        XCTAssertTrue(spy.transitions.isEmpty)
    }

    func testTraitsFollowAngle() async throws {
        try await apply("inner.portrait", angle: 90)
        XCTAssertEqual(spy.traitCollection.duoPosture, .halfOpen)
        XCTAssertEqual(spy.traitCollection.duoHinge.angle, 90)
        XCTAssertEqual(spy.traitCollection.duoHinge.rect, DuoPreview.hingeRect)
        XCTAssertFalse(DuoPreview.hingeRect.isNull)

        DuoPreview.setHingeAngle(180, animated: false)
        XCTAssertEqual(spy.traitCollection.duoPosture, .open)
        XCTAssertEqual(DuoPreview.posture, .open)

        DuoPreview.fold(animation: .none)
        XCTAssertEqual(spy.traitCollection.duoPosture, .closed)
        XCTAssertTrue(spy.traitCollection.duoHinge.rect.isNull)
    }

    func testInstantAnimationEndsAtTargetSize() async throws {
        try await apply("inner.landscape")
        await DuoPreview.transition(to: DuoState.preset("outer")!, animation: DuoAnimation(kind: .none))
        window.layoutIfNeeded()
        XCTAssertEqual(navigation.view.bounds.size, CGSize(width: 466, height: 678))
        XCTAssertEqual(spy.transitions.last, CGSize(width: 466, height: 678))
    }

    func testRealisticAnimationSwitchesDisplay() async throws {
        try await apply("outer")
        await DuoPreview.transition(to: DuoState.preset("inner.portrait")!, animation: .realistic(duration: 0.15))
        window.layoutIfNeeded()
        XCTAssertEqual(navigation.view.bounds.size, CGSize(width: 626, height: 890))
        XCTAssertTrue(try host.overlay.isHidden)
    }

    func testObserversPublisherAndStream() async throws {
        var changes: [(Double, Double)] = []
        let token = DuoPreview.onStateChange { old, new in changes.append((old.hingeAngle, new.hingeAngle)) }
        var published: [Double] = []
        let cancellable = DuoPreview.statePublisher.sink { published.append($0.hingeAngle) }
        var iterator = DuoPreview.stateStream.makeAsyncIterator()
        _ = await iterator.next()

        DuoPreview.setHingeAngle(90, animated: false)
        XCTAssertEqual(changes.last?.1, 90)
        XCTAssertEqual(published.last, 90)
        let next = await iterator.next()
        XCTAssertEqual(next?.hingeAngle, 90)

        token.cancel()
        DuoPreview.setHingeAngle(100, animated: false)
        XCTAssertEqual(changes.count, 1)
        cancellable.cancel()
    }

    func testQueuedRequestsApplyLatest() async throws {
        try await apply("inner.landscape")
        DuoPreview.set(DuoState.preset("outer")!, animation: .realistic(duration: 0.05))
        DuoPreview.set(DuoState.preset("inner.portrait")!, animation: .none)
        await DuoPreview.transition(to: DuoState.preset("inner.split.half")!, animation: .none)
        window.layoutIfNeeded()
        XCTAssertEqual(navigation.view.bounds.size, CGSize(width: 445, height: 626))
    }

    func testReportMatchesState() async throws {
        try await apply("inner.split.stacked")
        let report = Reporter.makeReport()
        XCTAssertEqual(report.state, "inner.split.stacked")
        XCTAssertEqual(report.contentSize, [626, 445])
        XCTAssertEqual(report.sizeClass.h, "compact")
        XCTAssertEqual(report.posture, "open")
    }

    func testRemoteCommands() async throws {
        try await apply("inner.landscape")
        DarwinNotificationListener.handle("com.duolab.anim.none")
        DarwinNotificationListener.handle("com.duolab.state.inner.portrait")
        XCTAssertEqual(DuoPreview.state.token(), "inner.portrait")
        DarwinNotificationListener.handle("com.duolab.angle.90")
        XCTAssertEqual(DuoPreview.hingeAngle, 90)
        DarwinNotificationListener.handle("com.duolab.fold")
        XCTAssertEqual(DuoPreview.posture, .closed)
        DarwinNotificationListener.handle("com.duolab.option.frame.off")
        XCTAssertFalse(runtime.options.showFrame)
    }

    func testSideToolbarMovesBarButtonsAndAddsSafeArea() async throws {
        var tapped = 0
        let detail = UIViewController()
        detail.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "star"),
                                                                    primaryAction: UIAction { _ in tapped += 1 })
        navigation.pushViewController(detail, animated: false)
        try await apply("inner.landscape")
        let host = try host
        host.sideToolbar.update()
        let width = runtime.config.sideToolbarWidth

        XCTAssertTrue(host.sideToolbar.isActive)
        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertEqual(navigation.additionalSafeAreaInsets.right, width)
        let buttons = allButtons(in: host.sideToolbar.view)
        XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Back", "Bar item"])
        buttons[1].sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(tapped, 1)

        // Half-open keeps the app's own bars.
        DuoPreview.setHingeAngle(90, animated: false)
        XCTAssertFalse(host.sideToolbar.isActive)
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertEqual(navigation.additionalSafeAreaInsets.right, 0)

        try await apply("outer")
        host.sideToolbar.update()
        XCTAssertTrue(navigation.isNavigationBarHidden)
        allButtons(in: host.sideToolbar.view).first?.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(navigation.viewControllers.count, 1, "back button pops")

        try await apply("inner.portrait")
        XCTAssertFalse(host.sideToolbar.isActive)
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }

    private func allButtons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { ($0 as? UIButton).map { [$0] } ?? allButtons(in: $0) }
    }

    func testImageDiffCountsChangedPixels() {
        let size = CGSize(width: 20, height: 10)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let a = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        let b = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 5, height: 2))
        }
        XCTAssertEqual(ImageDiff.compare(a, a, threshold: 10).changedPixels, 0)
        let diff = ImageDiff.compare(a, b, threshold: 10)
        XCTAssertEqual(diff.changedPixels, 10)
        XCTAssertNotNil(diff.highlight)
        let masked = ImageDiff.compare(ImageDiff.masking(a, rects: [CGRect(x: 0, y: 0, width: 5, height: 2)]),
                                       ImageDiff.masking(b, rects: [CGRect(x: 0, y: 0, width: 5, height: 2)]), threshold: 10)
        XCTAssertEqual(masked.changedPixels, 0)
    }

    func testStressTestWritesReport() async throws {
        DuoPreview.track(spy)
        let configuration = DuoStressTestConfiguration(cycles: 2, sequence: ["inner.landscape", "outer"], animation: .none,
                                                       delay: 0.01, channelThreshold: 24)
        let result = await DuoPreview.runStressTest(configuration)
        let url = try XCTUnwrap(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((json["steps"] as? [Any])?.count, 4)
        XCTAssertEqual(json["transitions"] as? Int, 4)
        XCTAssertNotNil((json["lifecycle"] as? [String: Any])?.keys.first { $0.contains("SpyViewController") })
    }

    func testCaptureAllStates() async throws {
        runtime.options.blurOnFold = false
        let result = await DuoPreview.captureAllStates()
        let directory = try XCTUnwrap(result)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(files.count, runtime.config.tools.screenshotStates.count)
    }
}
