import Foundation

/// Listens for Darwin notifications so the emulator can be driven externally (DuoLab, `notifyutil`).
///
/// ```
/// xcrun simctl spawn booted notifyutil -p com.duolab.fold
/// xcrun simctl spawn booted notifyutil -p com.duolab.state.inner.portrait
/// xcrun simctl spawn booted notifyutil -p com.duolab.angle.90
/// xcrun simctl spawn booted notifyutil -p com.duolab.option.3d.on
/// ```
@MainActor
final class DarwinNotificationListener {
    static let prefix = "com.duolab."
    private var names: [String] = []

    init(runtime: DuoRuntime) {
        let config = runtime.config
        var names = config.presets.map { "\(Self.prefix)state.\($0.id)" }
        names += ["fold", "unfold", "report"].map { Self.prefix + $0 }
        names += DuoAnimation.Kind.allCases.map { "\(Self.prefix)anim.\($0.rawValue)" }
        names += Self.options.keys.flatMap { ["\(Self.prefix)option.\($0).on", "\(Self.prefix)option.\($0).off"] }
        let step = max(Int(config.angles.remoteStep), 1)
        names += stride(from: 0, through: 180, by: step).map { "\(Self.prefix)angle.\($0)" }
        self.names = names

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            CFNotificationCenterAddObserver(center, observer, { _, _, name, _, _ in
                guard let raw = name?.rawValue as String? else { return }
                Task { @MainActor in DarwinNotificationListener.handle(raw) }
            }, name as CFString, nil, .deliverImmediately)
        }
        duoPrint("listening for \(names.count) Darwin notifications (\(Self.prefix)*)")
    }

    isolated deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
    }

    /// `com.duolab.option.<name>.on|off`
    static let options: [String: WritableKeyPath<DuoOptions, Bool>] = [
        "frame": \.showFrame, "hinge": \.showHinge, "3d": \.show3D, "blur": \.blurOnFold, "sizes": \.showSizes, "hud": \.hudVisible, "advanced": \.hudAdvanced,
    ]

    static func handle(_ name: String) {
        guard name.hasPrefix(prefix) else { return }
        let runtime = DuoRuntime.shared
        let command = String(name.dropFirst(prefix.count))
        duoPrint("remote: \(command)")
        if command == "fold" {
            DuoPreview.fold(animation: runtime.animation)
        } else if command == "unfold" {
            DuoPreview.unfold(animation: runtime.animation)
        } else if command == "report" {
            Reporter.write()
        } else if command.hasPrefix("state.") {
            DuoPreview.setPreset(String(command.dropFirst("state.".count)), animation: runtime.animation)
        } else if command.hasPrefix("angle."), let angle = Double(command.dropFirst("angle.".count)) {
            DuoPreview.setHingeAngle(angle, animated: true)
        } else if command.hasPrefix("option.") {
            let parts = command.split(separator: ".").map(String.init)
            guard parts.count == 3, let keyPath = options[parts[1]] else { return }
            runtime.options[keyPath: keyPath] = parts[2] == "on"
            if keyPath == \.hudVisible { runtime.hud?.setVisible(runtime.options.hudVisible) }
            runtime.hud?.stateDidChange()
        } else if command.hasPrefix("anim."), let kind = DuoAnimation.Kind(rawValue: String(command.dropFirst("anim.".count))) {
            runtime.animation = DuoAnimation(kind: kind)
            runtime.hud?.stateDidChange()
        }
    }
}
