import CoreGraphics
import Foundation
import os

/// Size class value used by preset rules.
public enum DuoSizeClass: String, Codable, Sendable, Equatable {
    case compact, regular
}

/// Size class rule of a preset.
public struct DuoSizeClassRule: Codable, Sendable, Equatable {
    public var horizontal: DuoSizeClass
    public var vertical: DuoSizeClass
}

/// Edge insets in points, decoded from JSON.
public struct DuoInsets: Codable, Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public static let zero = DuoInsets(top: 0, left: 0, bottom: 0, right: 0)
}

/// Axis of the hinge on a physical screen.
public enum DuoHingeAxis: String, Codable, Sendable, Equatable {
    /// No hinge crosses this screen.
    case none
    /// Vertical line in the middle of the screen (book-style fold).
    case vertical
    /// Horizontal line in the middle of the screen.
    case horizontal
}

/// One entry of `DuoPresets.json`.
public struct DuoPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var display: DuoState.Display
    public var orientation: DuoState.Orientation?
    public var split: DuoState.Split
    public var width: Double
    public var height: Double
    /// Parent physical screen for presets that occupy only part of it (split).
    public var screen: String?
    public var originX: Double
    public var originY: Double
    public var safeAreaInsets: DuoInsets
    public var sizeClass: DuoSizeClassRule
    public var hinge: DuoHingeAxis
    /// Move navigation bar / toolbar buttons into a strip on the right edge (see `sideToolbarWidth`).
    public var sideToolbar: Bool

    public var size: CGSize { CGSize(width: width, height: height) }
    public var displayTitle: String { title ?? id }

    private enum CodingKeys: String, CodingKey {
        case id, title, display, orientation, split, width, height, screen, originX, originY, safeAreaInsets, sizeClass, hinge
        case sideToolbar
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        display = try c.decode(DuoState.Display.self, forKey: .display)
        orientation = try c.decodeIfPresent(DuoState.Orientation.self, forKey: .orientation)
        split = try c.decodeIfPresent(DuoState.Split.self, forKey: .split) ?? .none
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        screen = try c.decodeIfPresent(String.self, forKey: .screen)
        originX = try c.decodeIfPresent(Double.self, forKey: .originX) ?? 0
        originY = try c.decodeIfPresent(Double.self, forKey: .originY) ?? 0
        safeAreaInsets = try c.decodeIfPresent(DuoInsets.self, forKey: .safeAreaInsets) ?? .zero
        sizeClass = try c.decode(DuoSizeClassRule.self, forKey: .sizeClass)
        hinge = try c.decodeIfPresent(DuoHingeAxis.self, forKey: .hinge) ?? .none
        sideToolbar = try c.decodeIfPresent(Bool.self, forKey: .sideToolbar) ?? false
    }
}

/// Full configuration loaded from `DuoPresets.json`. All sizes, thresholds and timings come from here.
public struct DuoConfiguration: Codable, Sendable, Equatable {
    public struct PostureThresholds: Codable, Sendable, Equatable {
        /// Angles below this value are `.closed`.
        public var closedBelow: Double
        /// Angles above this value are `.open`.
        public var openAbove: Double
    }

    public struct Angles: Codable, Sendable, Equatable {
        public var closed: Double
        public var halfOpen: Double
        public var open: Double
        public var keyboardStep: Double
        public var remoteStep: Double
    }

    public struct Animation: Codable, Sendable, Equatable {
        public var duration: Double
        public var minimumDurationFraction: Double
        public var continuousSteps: Int
        public var continuousStepPause: Double
        public var perspective: Double
        public var shadeOpacity: Double
        public var halfOpen3DFPS: Double
        /// Gaussian blur radius (pt) of fold leaves in `.realistic` when blur is on.
        public var blurRadius: Double
        /// Part of the animation (0…1) over which the blur ramps up.
        public var blurRampFraction: Double
        /// Fade from the blurred final snapshot to live content, seconds.
        public var blurFadeOut: Double
    }

    public struct Tools: Codable, Sendable, Equatable {
        public var settleDelay: Double
        public var screenshotStates: [String]
        public var stressSequence: [String]
        public var stressCycles: Int
        public var stressDelay: Double
        public var diffChannelThreshold: Int
    }

    public var version: Int
    public var scale: Double
    public var cornerRadius: Double
    public var bezelWidth: Double
    public var hingeWidth: Double
    public var displaySwitchAngle: Double
    /// Width of the right-edge strip that receives navigation buttons for presets with `sideToolbar`.
    public var sideToolbarWidth: Double
    public var posture: PostureThresholds
    public var angles: Angles
    public var animation: Animation
    public var tools: Tools
    public var presets: [DuoPreset]

    public enum LoadError: Error, CustomStringConvertible {
        case missingOuterPreset
        case missingInnerPreset
        case unknownScreen(presetID: String, screen: String)
        case duplicateID(String)

        public var description: String {
            switch self {
            case .missingOuterPreset: "DuoPresets.json must contain a preset with display \"outer\""
            case .missingInnerPreset: "DuoPresets.json must contain an inner preset with split \"none\""
            case let .unknownScreen(id, screen): "Preset \(id) references unknown screen \(screen)"
            case let .duplicateID(id): "Duplicate preset id \(id)"
            }
        }
    }

    /// Decodes and validates a configuration.
    public static func decode(_ data: Data) throws -> DuoConfiguration {
        let config = try JSONDecoder().decode(DuoConfiguration.self, from: data)
        try config.validate()
        return config
    }

    /// Loads a configuration from a file URL.
    public static func load(from url: URL) throws -> DuoConfiguration {
        try decode(Data(contentsOf: url))
    }

    /// URL of the JSON bundled with the package.
    public static var bundledURL: URL? {
        Bundle.module.url(forResource: "DuoPresets", withExtension: "json")
    }

    /// The configuration bundled with the package.
    public static let bundled: DuoConfiguration = {
        guard let url = bundledURL else { fatalError("DuoPreviewKit: DuoPresets.json is missing from the bundle") }
        do { return try load(from: url) } catch { fatalError("DuoPreviewKit: invalid bundled DuoPresets.json: \(error)") }
    }()

    private static let storage = OSAllocatedUnfairLock<DuoConfiguration?>(initialState: nil)

    /// Configuration currently in use (bundled unless replaced with `DuoPreview.configure(presetsURL:)`).
    public static var current: DuoConfiguration {
        get { storage.withLock { $0 } ?? bundled }
        set { storage.withLock { $0 = newValue } }
    }

    public func validate() throws {
        var seen = Set<String>()
        for preset in presets {
            guard seen.insert(preset.id).inserted else { throw LoadError.duplicateID(preset.id) }
        }
        guard presets.contains(where: { $0.display == .outer }) else { throw LoadError.missingOuterPreset }
        guard presets.contains(where: { $0.display == .inner && $0.split == .none }) else { throw LoadError.missingInnerPreset }
        for preset in presets {
            if let screen = preset.screen, !seen.contains(screen) {
                throw LoadError.unknownScreen(presetID: preset.id, screen: screen)
            }
        }
    }

    public func preset(id: String) -> DuoPreset? {
        presets.first { $0.id == id }
    }

    /// Picks the preset describing the given state (ignores `customSize`).
    public func resolvePreset(for state: DuoState) -> DuoPreset {
        if state.activeDisplay(in: self) == .outer {
            return presets.first { $0.display == .outer }!
        }
        let inner = presets.filter { $0.display == .inner }
        return inner.first { $0.split == state.split && $0.orientation == state.orientation }
            ?? inner.first { $0.split == state.split && $0.orientation == nil }
            ?? inner.first { $0.split == .none && $0.orientation == state.orientation }
            ?? inner.first { $0.split == .none }!
    }
}
