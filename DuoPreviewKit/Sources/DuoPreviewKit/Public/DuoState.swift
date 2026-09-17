import CoreGraphics
import Foundation

/// Physical posture of the device derived from the hinge angle.
public enum DuoPosture: String, Sendable, Equatable, Codable, CaseIterable {
    /// Hinge angle below `posture.closedBelow` (≈0°).
    case closed
    /// Between the closed and open thresholds (≈90°).
    case halfOpen
    /// Reserved for angles above 180°. Not supported yet: never produced by the model.
    case tent
    /// Hinge angle above `posture.openAbove` (≈180°).
    case open
}

/// Emulated Duo state. Stored values are the input; `activeDisplay`, `posture` and `contentSize`
/// are derived from them using ``DuoConfiguration/current``.
public struct DuoState: Sendable, Equatable, Codable {
    public enum Orientation: String, Codable, Sendable, CaseIterable {
        case landscape, portrait
    }

    public enum Split: String, Codable, Sendable, CaseIterable {
        case none, half, stacked
    }

    public enum Display: String, Codable, Sendable {
        case outer, inner
    }

    private var angle: Double

    /// Hinge angle in degrees, clamped to 0...180.
    public var hingeAngle: Double {
        get { angle }
        set { angle = Self.clamp(newValue) }
    }

    /// Orientation used by the inner screen.
    public var orientation: Orientation
    /// Split mode used by the inner screen.
    public var split: Split
    /// Arbitrary size that overrides the preset size.
    public var customSize: CGSize?

    public init(hingeAngle: Double = 180, orientation: Orientation = .landscape, split: Split = .none, customSize: CGSize? = nil) {
        self.angle = Self.clamp(hingeAngle)
        self.orientation = orientation
        self.split = split
        self.customSize = customSize
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 180 }
        return min(max(value, 0), 180)
    }

    private enum CodingKeys: String, CodingKey {
        case angle = "hingeAngle", orientation, split, customSize
    }

    // MARK: Derived values

    /// `.outer` when the angle is below `displaySwitchAngle`.
    public var activeDisplay: Display { activeDisplay(in: .current) }
    /// Posture computed from the angle and JSON thresholds.
    public var posture: DuoPosture { posture(in: .current) }
    /// Size of the content area.
    public var contentSize: CGSize { layout(in: .current).contentFrame.size }
    /// Id of the preset that describes this state.
    public var presetID: String { DuoConfiguration.current.resolvePreset(for: self).id }

    public func activeDisplay(in config: DuoConfiguration) -> Display {
        hingeAngle < config.displaySwitchAngle ? .outer : .inner
    }

    public func posture(in config: DuoConfiguration) -> DuoPosture {
        if hingeAngle < config.posture.closedBelow { return .closed }
        if hingeAngle > config.posture.openAbove { return .open }
        return .halfOpen
    }

    public func contentSize(in config: DuoConfiguration) -> CGSize {
        layout(in: config).contentFrame.size
    }

    /// Full geometry for this state.
    public func layout(in config: DuoConfiguration) -> DuoLayout {
        let preset = config.resolvePreset(for: self)
        let display = activeDisplay(in: config)

        let screenSize: CGSize
        let contentFrame: CGRect
        let axis: DuoHingeAxis
        if let customSize {
            screenSize = customSize
            contentFrame = CGRect(origin: .zero, size: customSize)
            axis = preset.screen == nil ? preset.hinge : .none
        } else if let screenID = preset.screen, let screen = config.preset(id: screenID) {
            screenSize = screen.size
            contentFrame = CGRect(x: preset.originX, y: preset.originY, width: preset.width, height: preset.height)
            axis = screen.hinge
        } else {
            screenSize = preset.size
            contentFrame = CGRect(origin: .zero, size: preset.size)
            axis = preset.hinge
        }

        var hingeInScreen = CGRect.null
        if display == .inner {
            let w = config.hingeWidth
            switch axis {
            case .vertical:
                hingeInScreen = CGRect(x: screenSize.width / 2 - w / 2, y: 0, width: w, height: screenSize.height)
            case .horizontal:
                hingeInScreen = CGRect(x: 0, y: screenSize.height / 2 - w / 2, width: screenSize.width, height: w)
            case .none:
                break
            }
        }

        // The hinge belongs to the content only when its center line lies strictly inside the content.
        var hingeInContent = CGRect.null
        if !hingeInScreen.isNull {
            let inside: Bool = switch axis {
            case .vertical: hingeInScreen.midX > contentFrame.minX && hingeInScreen.midX < contentFrame.maxX
            case .horizontal: hingeInScreen.midY > contentFrame.minY && hingeInScreen.midY < contentFrame.maxY
            case .none: false
            }
            if inside {
                hingeInContent = hingeInScreen.intersection(contentFrame).offsetBy(dx: -contentFrame.minX, dy: -contentFrame.minY)
            }
        }

        return DuoLayout(
            preset: preset,
            display: display,
            posture: posture(in: config),
            screenSize: screenSize,
            contentFrame: contentFrame,
            hingeAxis: display == .inner ? axis : .none,
            hingeRectInScreen: hingeInScreen,
            hingeRect: hingeInContent,
            safeAreaInsets: preset.safeAreaInsets,
            sizeClass: preset.sizeClass
        )
    }

    // MARK: Presets and tokens

    /// Returns a copy of this state switched to the given preset. Inner presets keep the current angle
    /// when the inner screen is already active; otherwise the angle becomes `angles.open`.
    public func applying(preset: DuoPreset, in config: DuoConfiguration = .current) -> DuoState {
        var copy = self
        copy.customSize = nil
        switch preset.display {
        case .outer:
            copy.hingeAngle = config.angles.closed
        case .inner:
            if activeDisplay(in: config) == .outer { copy.hingeAngle = config.angles.open }
            copy.split = preset.split
            if let orientation = preset.orientation { copy.orientation = orientation }
        }
        return copy
    }

    /// State for a preset id (starting from the default open state).
    public static func preset(_ id: String, in config: DuoConfiguration = .current) -> DuoState? {
        guard let preset = config.preset(id: id) else { return nil }
        return DuoState().applying(preset: preset, in: config)
    }

    /// Parses a token like `inner.landscape` or `inner.landscape@90` (preset id + optional angle).
    public static func parse(_ token: String, in config: DuoConfiguration = .current) -> DuoState? {
        let parts = token.split(separator: "@", maxSplits: 1).map(String.init)
        guard var state = preset(parts[0], in: config) else { return nil }
        if parts.count == 2 {
            guard let angle = Double(parts[1]) else { return nil }
            state.hingeAngle = angle
        }
        return state
    }

    /// Short human-readable token (inverse of ``parse(_:in:)``).
    public func token(in config: DuoConfiguration = .current) -> String {
        let id = config.resolvePreset(for: self).id
        let base = customSize.map { "custom(\(Int($0.width))x\(Int($0.height)))" } ?? id
        let isDefaultAngle = (activeDisplay(in: config) == .outer && hingeAngle == config.angles.closed)
            || hingeAngle == config.angles.open
        return isDefaultAngle ? base : "\(base)@\(Int(hingeAngle.rounded()))"
    }
}

/// Resolved geometry of a ``DuoState``.
public struct DuoLayout: Sendable, Equatable {
    public var preset: DuoPreset
    public var display: DuoState.Display
    public var posture: DuoPosture
    /// Size of the physical screen area (the full inner screen for split presets).
    public var screenSize: CGSize
    /// Content frame inside the screen.
    public var contentFrame: CGRect
    public var hingeAxis: DuoHingeAxis
    /// Hinge in screen coordinates, `.null` when the active screen has no hinge.
    public var hingeRectInScreen: CGRect
    /// Hinge in content coordinates, `.null` when the hinge does not cross the content.
    public var hingeRect: CGRect
    public var safeAreaInsets: DuoInsets
    public var sizeClass: DuoSizeClassRule
}
