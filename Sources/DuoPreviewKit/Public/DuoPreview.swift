import Combine
import UIKit

/// How a state change is visualized.
public struct DuoAnimation: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        /// Snapshot leaves rotated in 3D, content switched at `displaySwitchAngle`.
        case realistic
        /// Instant change.
        case none
    }

    public var kind: Kind
    /// Duration of a full 0↔180° fold. `nil` uses `animation.duration` from JSON.
    public var duration: TimeInterval?
    public init(kind: Kind, duration: TimeInterval? = nil) {
        self.kind = kind
        self.duration = duration
    }

    /// Snapshot leaves in 3D, like on the device.
    public static let realistic = DuoAnimation(kind: .realistic)
    /// Instant change.
    public static let none = DuoAnimation(kind: .none)

    public static func realistic(duration: TimeInterval) -> DuoAnimation {
        DuoAnimation(kind: .realistic, duration: duration)
    }
}

/// Token returned by ``DuoPreview/onStateChange(_:)``. Call ``cancel()`` or release it to unsubscribe.
@MainActor
public final class DuoSubscription {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }

    isolated deinit {
        cancel()
    }
}

/// Entry point of DuoPreviewKit.
///
/// Every API is safe to call in release builds or when the emulator is not enabled: calls become no-ops and
/// getters describe a fully open device with the size of the window.
@MainActor
public enum DuoPreview {
    private static var forced = false

    // MARK: Enabling

    /// `true` in DEBUG builds unless turned off with the launch argument `-DuoPreviewOff` or env `DUO_PREVIEW=0`
    /// (``forceEnable()`` wins). Always `false` in release builds.
    public static var isEnabled: Bool {
        #if DEBUG
        if forced { return true }
        let info = ProcessInfo.processInfo
        return !info.arguments.contains("-DuoPreviewOff") && info.environment["DUO_PREVIEW"] != "0"
        #else
        return false
        #endif
    }

    /// Enables the emulator regardless of launch arguments (DEBUG builds only).
    public static func forceEnable() {
        forced = true
    }

    /// `true` after a successful ``install(in:)``.
    public static var isInstalled: Bool {
        isEnabled && DuoRuntime.shared.host != nil
    }

    /// Replaces the bundled presets with a custom JSON file.
    public static func configure(presetsURL: URL) throws {
        guard isEnabled else { return }
        let config = try DuoConfiguration.load(from: presetsURL)
        DuoRuntime.shared.replaceConfiguration(config)
    }

    // MARK: Installation

    /// Wraps `window.rootViewController` into the Duo host. Does nothing when disabled, when already installed,
    /// or when the window cannot fit the inner screen.
    public static func install(in window: UIWindow) {
        guard isEnabled else { return }
        DuoRuntime.shared.install(in: window)
    }

    // MARK: Reading

    /// Current (target) state.
    public static var state: DuoState {
        isEnabled ? DuoRuntime.shared.state : disabledState
    }

    public static var hingeAngle: Double {
        isEnabled ? DuoRuntime.shared.state.hingeAngle : 180
    }

    public static var posture: DuoPosture {
        isEnabled ? DuoRuntime.shared.state.posture(in: DuoRuntime.shared.config) : .open
    }

    /// Hinge area in content coordinates; `.null` when the active screen content has no hinge.
    public static var hingeRect: CGRect {
        isEnabled ? DuoRuntime.shared.state.layout(in: DuoRuntime.shared.config).hingeRect : .null
    }

    /// Size of the emulated content area (or the window size when disabled).
    public static var contentSize: CGSize {
        isEnabled ? DuoRuntime.shared.state.contentSize(in: DuoRuntime.shared.config) : keyWindowSize
    }

    /// Animation mode used by the HUD, keyboard and remote commands.
    public static var defaultAnimation: DuoAnimation {
        get { isEnabled ? DuoRuntime.shared.animation : .none }
        set { if isEnabled { DuoRuntime.shared.animation = newValue } }
    }

    // MARK: Control

    /// Changes the state.
    public static func set(_ state: DuoState, animation: DuoAnimation = .realistic) {
        guard isEnabled else { return }
        DuoRuntime.shared.set(state, animation: animation, completion: nil)
    }

    /// Changes the state and waits for the animation to finish.
    public static func transition(to state: DuoState, animation: DuoAnimation = .realistic) async {
        guard isEnabled else { return }
        await withCheckedContinuation { continuation in
            DuoRuntime.shared.set(state, animation: animation) { continuation.resume() }
        }
    }

    /// Switches to a preset from JSON by id.
    public static func setPreset(_ id: String, animation: DuoAnimation = .realistic) {
        guard isEnabled, let preset = DuoRuntime.shared.config.preset(id: id) else { return }
        set(DuoRuntime.shared.state.applying(preset: preset, in: DuoRuntime.shared.config), animation: animation)
    }

    /// Folds to `angles.closed` (outer screen).
    public static func fold(animation: DuoAnimation = .realistic) {
        guard isEnabled else { return }
        var s = DuoRuntime.shared.state
        s.hingeAngle = DuoRuntime.shared.config.angles.closed
        s.customSize = nil
        set(s, animation: animation)
    }

    /// Unfolds to `angles.open` (inner screen).
    public static func unfold(animation: DuoAnimation = .realistic) {
        guard isEnabled else { return }
        var s = DuoRuntime.shared.state
        s.hingeAngle = DuoRuntime.shared.config.angles.open
        set(s, animation: animation)
    }

    /// Changes only the hinge angle. `animated` uses ``defaultAnimation``.
    public static func setHingeAngle(_ angle: Double, animated: Bool) {
        guard isEnabled else { return }
        var s = DuoRuntime.shared.state
        s.hingeAngle = angle
        set(s, animation: animated ? DuoRuntime.shared.animation : .none)
    }

    // MARK: Subscriptions

    /// Calls `handler` after every state change. Keep the returned token alive.
    @discardableResult
    public static func onStateChange(_ handler: @escaping @MainActor (_ old: DuoState, _ new: DuoState) -> Void) -> DuoSubscription {
        guard isEnabled else { return DuoSubscription {} }
        return DuoRuntime.shared.addObserver(handler)
    }

    /// Combine publisher of the state (emits the current value on subscription).
    public static var statePublisher: AnyPublisher<DuoState, Never> {
        guard isEnabled else { return Just(disabledState).eraseToAnyPublisher() }
        return DuoRuntime.shared.subject.eraseToAnyPublisher()
    }

    /// Async sequence of states (starts with the current value).
    public static var stateStream: AsyncStream<DuoState> {
        guard isEnabled else {
            let state = disabledState
            return AsyncStream { $0.yield(state); $0.finish() }
        }
        return DuoRuntime.shared.makeStream()
    }

    // MARK: Tools

    /// Registers a view controller for lifecycle counters in stress test reports. Call from `viewDidLoad`.
    public static func track(_ viewController: UIViewController) {
        guard isEnabled else { return }
        LifecycleTracker.shared.track(viewController)
    }

    /// Excludes a view's area from stress test image diffs (clocks, animations).
    public static func stressTestIgnore(view: UIView) {
        guard isEnabled else { return }
        DuoRuntime.shared.ignoredViews.add(view)
    }

    /// Captures every state from `tools.screenshotStates`. Returns the output directory.
    @discardableResult
    public static func captureAllStates() async -> URL? {
        guard isInstalled else { return nil }
        return await Screenshotter.captureAllStates()
    }

    /// Runs the stress test. Returns the report URL.
    @discardableResult
    public static func runStressTest(_ configuration: DuoStressTestConfiguration? = nil) async -> URL? {
        guard isInstalled else { return nil }
        return await StressTest.run(configuration ?? DuoStressTestConfiguration(config: DuoRuntime.shared.config,
                                                                                 animation: DuoRuntime.shared.animation))
    }

    /// Shows or hides the debug HUD.
    public static func toggleHUD() {
        guard isInstalled else { return }
        DuoRuntime.shared.toggleHUD()
    }

    // MARK: Disabled fallbacks

    private static var keyWindowSize: CGSize {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.bounds.size ?? .zero
    }

    private static var disabledState: DuoState {
        DuoState(hingeAngle: 180, customSize: keyWindowSize)
    }
}
