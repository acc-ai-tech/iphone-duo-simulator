import UIKit

/// Hinge information exposed through traits and environment.
public struct DuoHinge: Sendable, Equatable {
    /// Hinge angle in degrees (0...180).
    public var angle: Double
    /// Hinge area in content coordinates, `.null` when the hinge does not cross the content.
    public var rect: CGRect

    public init(angle: Double, rect: CGRect) {
        self.angle = angle
        self.rect = rect
    }

    /// Value used when DuoPreview is disabled.
    public static let flat = DuoHinge(angle: 180, rect: .null)

    public static func == (lhs: DuoHinge, rhs: DuoHinge) -> Bool {
        // CGRect.null has infinite origin, compare explicitly.
        lhs.angle == rhs.angle && (lhs.rect == rhs.rect || (lhs.rect.isNull && rhs.rect.isNull))
    }
}

/// Trait carrying the emulated posture. Read with `traitCollection.duoPosture`.
///
/// All posture-dependent logic should go through this trait so the data source can be swapped
/// for a future Apple API without changing app code.
public struct DuoPostureTrait: UITraitDefinition {
    public static let defaultValue: DuoPosture = .open
    public static let identifier = "com.duopreviewkit.posture"
    public static let name = "DuoPosture"
    public static let affectsColorAppearance = false
}

/// Trait carrying hinge angle and rect. Read with `traitCollection.duoHinge`.
public struct DuoHingeTrait: UITraitDefinition {
    public static let defaultValue: DuoHinge = .flat
    public static let identifier = "com.duopreviewkit.hinge"
    public static let name = "DuoHinge"
    public static let affectsColorAppearance = false
}

public extension UITraitCollection {
    /// Emulated posture (``DuoPostureTrait``).
    var duoPosture: DuoPosture { self[DuoPostureTrait.self] }
    /// Emulated hinge (``DuoHingeTrait``).
    var duoHinge: DuoHinge { self[DuoHingeTrait.self] }
}

public extension UIMutableTraits {
    /// Emulated posture (``DuoPostureTrait``).
    var duoPosture: DuoPosture {
        get { self[DuoPostureTrait.self] }
        set { self[DuoPostureTrait.self] = newValue }
    }

    /// Emulated hinge (``DuoHingeTrait``).
    var duoHinge: DuoHinge {
        get { self[DuoHingeTrait.self] }
        set { self[DuoHingeTrait.self] = newValue }
    }
}
