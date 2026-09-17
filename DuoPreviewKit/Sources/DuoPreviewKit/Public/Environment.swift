import SwiftUI
import UIKit

/// Environment key bridged to ``DuoPostureTrait``.
public struct DuoPostureEnvironmentKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    public static let defaultValue: DuoPosture = .open

    public static func read(from traitCollection: UITraitCollection) -> DuoPosture {
        traitCollection[DuoPostureTrait.self]
    }

    public static func write(to mutableTraits: inout any UIMutableTraits, value: DuoPosture) {
        mutableTraits[DuoPostureTrait.self] = value
    }
}

/// Environment key bridged to ``DuoHingeTrait``.
public struct DuoHingeEnvironmentKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    public static let defaultValue: DuoHinge = .flat

    public static func read(from traitCollection: UITraitCollection) -> DuoHinge {
        traitCollection[DuoHingeTrait.self]
    }

    public static func write(to mutableTraits: inout any UIMutableTraits, value: DuoHinge) {
        mutableTraits[DuoHingeTrait.self] = value
    }
}

public extension EnvironmentValues {
    /// Emulated posture: `@Environment(\.duoPosture)`.
    var duoPosture: DuoPosture {
        get { self[DuoPostureEnvironmentKey.self] }
        set { self[DuoPostureEnvironmentKey.self] = newValue }
    }

    /// Emulated hinge: `@Environment(\.duoHinge)`.
    var duoHinge: DuoHinge {
        get { self[DuoHingeEnvironmentKey.self] }
        set { self[DuoHingeEnvironmentKey.self] = newValue }
    }
}
