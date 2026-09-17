import CoreGraphics
import XCTest
@testable import DuoPreviewKit

final class StateTests: XCTestCase {
    private let config = DuoConfiguration.bundled

    func testPostureThresholds() {
        XCTAssertEqual(DuoState(hingeAngle: 0).posture(in: config), .closed)
        XCTAssertEqual(DuoState(hingeAngle: 9.9).posture(in: config), .closed)
        XCTAssertEqual(DuoState(hingeAngle: 10).posture(in: config), .halfOpen)
        XCTAssertEqual(DuoState(hingeAngle: 90).posture(in: config), .halfOpen)
        XCTAssertEqual(DuoState(hingeAngle: 160).posture(in: config), .halfOpen)
        XCTAssertEqual(DuoState(hingeAngle: 160.1).posture(in: config), .open)
        XCTAssertEqual(DuoState(hingeAngle: 180).posture(in: config), .open)
    }

    func testAngleIsClamped() {
        XCTAssertEqual(DuoState(hingeAngle: -20).hingeAngle, 0)
        var state = DuoState()
        state.hingeAngle = 400
        XCTAssertEqual(state.hingeAngle, 180)
    }

    func testActiveDisplaySwitchesAtConfiguredAngle() {
        let sw = config.displaySwitchAngle
        XCTAssertEqual(DuoState(hingeAngle: sw - 0.1).activeDisplay(in: config), .outer)
        XCTAssertEqual(DuoState(hingeAngle: sw).activeDisplay(in: config), .inner)
    }

    func testContentSizeForEveryPreset() {
        for preset in config.presets {
            let state = DuoState.preset(preset.id, in: config)!
            XCTAssertEqual(state.contentSize(in: config), preset.size, preset.id)
            XCTAssertEqual(state.layout(in: config).preset.id, preset.id)
            XCTAssertEqual(state.layout(in: config).sizeClass, preset.sizeClass, preset.id)
        }
    }

    func testOuterIgnoresOrientationAndSplit() {
        let state = DuoState(hingeAngle: 0, orientation: .portrait, split: .stacked)
        XCTAssertEqual(state.layout(in: config).preset.id, "outer")
        XCTAssertEqual(state.contentSize(in: config), config.preset(id: "outer")!.size)
    }

    func testCustomSizeOverridesPreset() {
        let state = DuoState(hingeAngle: 180, customSize: CGSize(width: 700, height: 500))
        XCTAssertEqual(state.contentSize(in: config), CGSize(width: 700, height: 500))
        XCTAssertEqual(state.layout(in: config).hingeRect.midX, 350)
    }

    func testHingeRect() {
        let w = config.hingeWidth
        let landscape = DuoState.preset("inner.landscape", in: config)!.layout(in: config)
        XCTAssertEqual(landscape.hingeRect, CGRect(x: 445 - w / 2, y: 0, width: w, height: 626))

        let portrait = DuoState.preset("inner.portrait", in: config)!.layout(in: config)
        XCTAssertEqual(portrait.hingeRect, CGRect(x: 0, y: 445 - w / 2, width: 626, height: w))

        // Split presets end exactly at the hinge: it does not cross the content.
        XCTAssertTrue(DuoState.preset("inner.split.half", in: config)!.layout(in: config).hingeRect.isNull)
        XCTAssertTrue(DuoState.preset("inner.split.stacked", in: config)!.layout(in: config).hingeRect.isNull)
        XCTAssertTrue(DuoState.preset("outer", in: config)!.layout(in: config).hingeRect.isNull)
    }

    func testHingeRectStaysDuringHalfOpenAndDisappearsOnOuter() {
        var state = DuoState.preset("inner.landscape", in: config)!
        state.hingeAngle = 90
        XCTAssertFalse(state.layout(in: config).hingeRect.isNull)
        state.hingeAngle = config.displaySwitchAngle - 1
        XCTAssertTrue(state.layout(in: config).hingeRect.isNull)
    }

    func testApplyingPresetKeepsHalfOpenAngleOnInner() {
        var state = DuoState.preset("inner.landscape", in: config)!
        state.hingeAngle = 90
        let portrait = state.applying(preset: config.preset(id: "inner.portrait")!, in: config)
        XCTAssertEqual(portrait.hingeAngle, 90)
        XCTAssertEqual(portrait.orientation, .portrait)

        let outer = state.applying(preset: config.preset(id: "outer")!, in: config)
        XCTAssertEqual(outer.hingeAngle, config.angles.closed)
        // Unfolding from outer goes to the open angle and remembers the inner layout.
        let unfolded = outer.applying(preset: config.preset(id: "inner.split.half")!, in: config)
        XCTAssertEqual(unfolded.hingeAngle, config.angles.open)
        XCTAssertEqual(unfolded.split, .half)
    }

    func testTokens() {
        XCTAssertEqual(DuoState.parse("inner.portrait@90", in: config)?.hingeAngle, 90)
        XCTAssertEqual(DuoState.parse("inner.portrait@90", in: config)?.orientation, .portrait)
        XCTAssertNil(DuoState.parse("nope", in: config))
        XCTAssertNil(DuoState.parse("outer@x", in: config))
        for token in ["outer", "inner.landscape", "inner.split.stacked", "inner.portrait@90"] {
            XCTAssertEqual(DuoState.parse(token, in: config)?.token(in: config), token)
        }
    }

    func testCodableRoundTrip() throws {
        let state = DuoState(hingeAngle: 72, orientation: .portrait, split: .stacked, customSize: CGSize(width: 1, height: 2))
        let decoded = try JSONDecoder().decode(DuoState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }

    func testTentIsNeverProduced() {
        for angle in stride(from: 0.0, through: 180, by: 1) {
            XCTAssertNotEqual(DuoState(hingeAngle: angle).posture(in: config), .tent)
        }
    }
}
