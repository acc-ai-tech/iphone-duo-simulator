import UIKit

/// Writes `Library/Caches/duolab-report.json` (triggered by `com.duolab.report`).
@MainActor
enum Reporter {
    struct Report: Codable {
        struct SizeClass: Codable {
            var h: String
            var v: String
        }

        var state: String
        var contentSize: [Double]
        var angle: Double
        var posture: String
        var sizeClass: SizeClass
        var safeArea: [Double]
        var transitions: Int
        var timestamp: String
    }

    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("duolab-report.json")
    }

    static func makeReport() -> Report {
        let runtime = DuoRuntime.shared
        let state = runtime.state
        let layout = state.layout(in: runtime.config)
        let insets = runtime.host?.content.view.safeAreaInsets ?? .zero
        return Report(
            state: state.token(in: runtime.config),
            contentSize: [layout.contentFrame.width, layout.contentFrame.height],
            angle: state.hingeAngle,
            posture: layout.posture.rawValue,
            sizeClass: .init(h: layout.sizeClass.horizontal.rawValue, v: layout.sizeClass.vertical.rawValue),
            safeArea: [insets.top, insets.left, insets.bottom, insets.right],
            transitions: runtime.transitionCount,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func write() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(makeReport()).write(to: url, options: .atomic)
            duoPrint("report written to \(url.path)")
        } catch {
            duoPrint("report failed: \(error)")
        }
    }
}
