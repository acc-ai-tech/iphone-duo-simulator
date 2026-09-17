import CoreGraphics
import XCTest
@testable import DuoPreviewKit

final class PresetsTests: XCTestCase {
    func testBundledJSONParses() throws {
        let config = try DuoConfiguration.load(from: XCTUnwrap(DuoConfiguration.bundledURL))
        XCTAssertEqual(config.presets.map(\.id),
                       ["outer", "inner.landscape", "inner.portrait", "inner.split.half", "inner.split.stacked"])
        XCTAssertEqual(config.preset(id: "outer")?.size, CGSize(width: 466, height: 678))
        XCTAssertEqual(config.preset(id: "inner.landscape")?.size, CGSize(width: 890, height: 626))
        XCTAssertEqual(config.preset(id: "inner.portrait")?.size, CGSize(width: 626, height: 890))
        XCTAssertEqual(config.preset(id: "inner.split.half")?.size, CGSize(width: 445, height: 626))
        XCTAssertEqual(config.preset(id: "inner.split.stacked")?.size, CGSize(width: 626, height: 445))
        XCTAssertEqual(config.displaySwitchAngle, 40)
        XCTAssertEqual(config.scale, 3)
    }

    func testSizeClassRules() {
        let config = DuoConfiguration.bundled
        let compactRegular = DuoSizeClassRule(horizontal: .compact, vertical: .regular)
        let regularRegular = DuoSizeClassRule(horizontal: .regular, vertical: .regular)
        XCTAssertEqual(config.preset(id: "outer")?.sizeClass, compactRegular)
        XCTAssertEqual(config.preset(id: "inner.landscape")?.sizeClass, regularRegular)
        XCTAssertEqual(config.preset(id: "inner.portrait")?.sizeClass, regularRegular)
        XCTAssertEqual(config.preset(id: "inner.split.half")?.sizeClass, compactRegular)
        XCTAssertEqual(config.preset(id: "inner.split.stacked")?.sizeClass, compactRegular)
    }

    func testOverrideJSON() throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(DuoConfiguration.bundledURL))) as! [String: Any]
        json["displaySwitchAngle"] = 55
        var presets = json["presets"] as! [[String: Any]]
        presets[0]["width"] = 500
        presets[0].removeValue(forKey: "safeAreaInsets")
        presets[0]["safeAreaInsets"] = ["top": 44, "left": 0, "bottom": 20, "right": 0]
        json["presets"] = presets
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID()).json")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let config = try DuoConfiguration.load(from: url)
        XCTAssertEqual(config.displaySwitchAngle, 55)
        XCTAssertEqual(config.preset(id: "outer")?.width, 500)
        XCTAssertEqual(config.preset(id: "outer")?.safeAreaInsets.top, 44)
        XCTAssertEqual(DuoState(hingeAngle: 50).activeDisplay(in: config), .outer)
    }

    func testOptionalFieldsDefault() throws {
        let json = """
        {"id":"x","display":"inner","width":10,"height":20,"sizeClass":{"horizontal":"regular","vertical":"compact"}}
        """
        let preset = try JSONDecoder().decode(DuoPreset.self, from: Data(json.utf8))
        XCTAssertEqual(preset.split, .none)
        XCTAssertEqual(preset.hinge, .none)
        XCTAssertEqual(preset.safeAreaInsets, .zero)
        XCTAssertNil(preset.orientation)
    }

    func testValidation() throws {
        var config = DuoConfiguration.bundled
        config.presets.removeAll { $0.display == .outer }
        XCTAssertThrowsError(try config.validate())

        config = DuoConfiguration.bundled
        config.presets[3].screen = "missing"
        XCTAssertThrowsError(try config.validate())

        config = DuoConfiguration.bundled
        config.presets.append(config.presets[0])
        XCTAssertThrowsError(try config.validate())
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try DuoConfiguration.decode(Data("{\"version\":1}".utf8)))
    }
}
