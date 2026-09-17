import Combine
import UIKit
import os

let duoLog = Logger(subsystem: "DuoPreviewKit", category: "DuoPreview")

/// Logs to the unified log and to stdout (visible in the Xcode console and `simctl launch --console`).
func duoPrint(_ message: String) {
    duoLog.notice("\(message, privacy: .public)")
    print("[DuoPreview] \(message)")
}

/// Visual options toggled from the HUD. Persisted.
struct DuoOptions: Codable, Equatable {
    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DuoOptions()
        showFrame = try c.decodeIfPresent(Bool.self, forKey: .showFrame) ?? d.showFrame
        showHinge = try c.decodeIfPresent(Bool.self, forKey: .showHinge) ?? d.showHinge
        show3D = try c.decodeIfPresent(Bool.self, forKey: .show3D) ?? d.show3D
        blurOnFold = try c.decodeIfPresent(Bool.self, forKey: .blurOnFold) ?? d.blurOnFold
        sideToolbar = try c.decodeIfPresent(Bool.self, forKey: .sideToolbar) ?? d.sideToolbar
        showSizes = try c.decodeIfPresent(Bool.self, forKey: .showSizes) ?? d.showSizes
        hudVisible = try c.decodeIfPresent(Bool.self, forKey: .hudVisible) ?? d.hudVisible
        hudCollapsed = try c.decodeIfPresent(Bool.self, forKey: .hudCollapsed) ?? d.hudCollapsed
        hudAdvanced = try c.decodeIfPresent(Bool.self, forKey: .hudAdvanced) ?? d.hudAdvanced
    }

    var showFrame = true
    var showHinge = true
    var show3D = true
    var blurOnFold = true
    var sideToolbar = true
    var showSizes = true
    var hudVisible = true
    var hudCollapsed = false
    var hudAdvanced = false
}

@MainActor
final class DuoRuntime {
    static let shared = DuoRuntime()

    private(set) var config: DuoConfiguration
    private(set) var state: DuoState
    var animation: DuoAnimation { didSet { persist() } }
    var options: DuoOptions { didSet { persist(); host?.optionsDidChange(); hud?.stateDidChange() } }
    /// Height at the top of the host occupied by the docked HUD; the device is centered below it when it fits.
    var hudTopInset: CGFloat = 0 { didSet { if hudTopInset != oldValue { host?.view.setNeedsLayout() } } }
    private(set) var transitionCount = 0

    weak var host: DuoHostViewController?
    var hud: HUDController?
    var remote: DarwinNotificationListener?
    let ignoredViews = NSHashTable<UIView>.weakObjects()
    let subject: CurrentValueSubject<DuoState, Never>

    private var observers: [UUID: (DuoState, DuoState) -> Void] = [:]
    private var continuations: [UUID: AsyncStream<DuoState>.Continuation] = [:]
    private var queued: (state: DuoState, animation: DuoAnimation, completions: [() -> Void])?
    private(set) var isTransitioning = false
    let defaults = UserDefaults(suiteName: "com.duopreviewkit") ?? .standard

    private enum Keys {
        static let state = "state"
        static let animation = "animation"
        static let options = "options"
    }

    private init() {
        config = .current
        let decoder = JSONDecoder()
        state = defaults.data(forKey: Keys.state).flatMap { try? decoder.decode(DuoState.self, from: $0) } ?? DuoState()
        animation = defaults.data(forKey: Keys.animation).flatMap { try? decoder.decode(DuoAnimation.self, from: $0) } ?? .realistic
        options = defaults.data(forKey: Keys.options).flatMap { try? decoder.decode(DuoOptions.self, from: $0) } ?? DuoOptions()
        subject = CurrentValueSubject(state)
    }

    // MARK: Install

    func install(in window: UIWindow) {
        if window.rootViewController is DuoHostViewController { return }
        guard let root = window.rootViewController else {
            duoPrint("install(in:) skipped: window has no rootViewController yet")
            return
        }
        let needed = config.presets.reduce(CGSize.zero) { size, preset in
            CGSize(width: max(size.width, preset.width), height: max(size.height, preset.height))
        }
        let bezel = config.bezelWidth * 2
        let available = window.bounds.size
        let minimumScale = 0.5
        // The device is scaled down to fit smaller windows; below 50% it is not useful anymore.
        guard UIDevice.current.userInterfaceIdiom == .pad,
              available.width >= (needed.width + bezel) * minimumScale,
              available.height >= (needed.height + bezel) * minimumScale else {
            duoPrint("⚠️ not enabled: window \(Int(available.width))×\(Int(available.height)) is too small for Duo screens "
                + "\(Int(needed.width + bezel))×\(Int(needed.height + bezel)) even at 50%. Use an iPad in full screen.")
            return
        }
        if available.width < needed.width + bezel || available.height < needed.height + bezel {
            duoPrint("window \(Int(available.width))×\(Int(available.height)) is smaller than Duo screens; "
                + "the device is shown scaled down (content keeps exact point sizes)")
        }

        let host = DuoHostViewController(content: root, runtime: self)
        window.rootViewController = host
        self.host = host
        duoPrint("installed. state=\(state.token(in: config)) animation=\(animation.kind.rawValue)")

        if let scene = window.windowScene {
            // The panel is always shown on launch; ⌘⇧D hides it for the current session.
            options.hudVisible = true
            hud = HUDController(scene: scene, runtime: self)
            hud?.setVisible(options.hudVisible)
        }
        if remote == nil {
            remote = DarwinNotificationListener(runtime: self)
        }
    }

    func replaceConfiguration(_ newConfig: DuoConfiguration) {
        DuoConfiguration.current = newConfig
        config = newConfig
        host?.performTransition(to: state, duration: 0)
        subject.send(state)
    }

    // MARK: State

    func set(_ newState: DuoState, animation: DuoAnimation, completion: (() -> Void)?) {
        if isTransitioning {
            // Latest request wins; earlier queued completions still fire.
            var completions = queued?.completions ?? []
            completion.map { completions.append($0) }
            queued = (newState, animation, completions)
            return
        }
        let old = state
        guard newState != old else {
            completion?()
            return
        }
        commit(newState)
        guard let host else {
            completion?()
            return
        }
        isTransitioning = true
        transitionCount += 1
        host.transition(from: old, to: newState, animation: animation) { [weak self] in
            guard let self else { return }
            self.isTransitioning = false
            completion?()
            if let next = self.queued {
                self.queued = nil
                self.set(next.state, animation: next.animation) {
                    next.completions.forEach { $0() }
                }
            }
        }
    }

    private func commit(_ newState: DuoState) {
        let old = state
        state = newState
        persist()
        for observer in observers.values { observer(old, newState) }
        subject.send(newState)
        for continuation in continuations.values { continuation.yield(newState) }
        hud?.stateDidChange()
    }

    func addObserver(_ handler: @escaping @MainActor (DuoState, DuoState) -> Void) -> DuoSubscription {
        let id = UUID()
        observers[id] = handler
        return DuoSubscription { [weak self] in self?.observers[id] = nil }
    }

    func makeStream() -> AsyncStream<DuoState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<DuoState>.makeStream(bufferingPolicy: .bufferingNewest(16))
        continuation.yield(state)
        continuations[id] = continuation
        continuation.onTermination = { _ in
            Task { @MainActor in DuoRuntime.shared.continuations[id] = nil }
        }
        return stream
    }

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(state), forKey: Keys.state)
        defaults.set(try? encoder.encode(animation), forKey: Keys.animation)
        defaults.set(try? encoder.encode(options), forKey: Keys.options)
    }

    // MARK: Commands (HUD, keyboard, remote)

    func toggleHUD() {
        options.hudVisible.toggle()
        hud?.setVisible(options.hudVisible)
    }

    func toggleFold() {
        if state.activeDisplay(in: config) == .outer {
            DuoPreview.unfold(animation: animation)
        } else {
            DuoPreview.fold(animation: animation)
        }
    }

    func selectPreset(at index: Int) {
        guard config.presets.indices.contains(index) else { return }
        DuoPreview.setPreset(config.presets[index].id, animation: animation)
    }

    func stepAngle(by delta: Double) {
        DuoPreview.setHingeAngle(state.hingeAngle + delta, animated: true)
    }

    func cycleAnimation() {
        let all = DuoAnimation.Kind.allCases
        let next = all[(all.firstIndex(of: animation.kind)! + 1) % all.count]
        animation = DuoAnimation(kind: next)
        duoPrint("animation → \(next.rawValue)")
        hud?.stateDidChange()
    }

    #if DEBUG
    /// Resets in-memory state for unit tests.
    func resetForTesting() {
        config = .current
        state = DuoState()
        animation = .none
        options = DuoOptions()
        observers = [:]
        queued = nil
        isTransitioning = false
        subject.send(state)
    }
    #endif
}
