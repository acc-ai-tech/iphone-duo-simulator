import UIKit

@MainActor
enum Screenshotter {
    /// `Documents/DuoPreview/<name>/`
    static func makeOutputDirectory(_ name: String) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("DuoPreview", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// Renders the content container (without HUD, frame or hinge overlay).
    static func captureContent(host: DuoHostViewController) -> UIImage {
        let view = host.contentContainer
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    static func settle(_ config: DuoConfiguration) async {
        try? await Task.sleep(for: .seconds(config.tools.settleDelay))
    }

    static func fileName(index: Int, token: String) -> String {
        let safe = token.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: "/", with: "_")
        return String(format: "%02d-%@.png", index, safe)
    }

    static func captureAllStates() async -> URL? {
        let runtime = DuoRuntime.shared
        guard let host = runtime.host else { return nil }
        let config = runtime.config
        let original = runtime.state
        do {
            let directory = try makeOutputDirectory(timestamp())
            for (index, token) in config.tools.screenshotStates.enumerated() {
                guard let state = DuoState.parse(token, in: config) else {
                    duoPrint("screenshots: unknown state token \(token)")
                    continue
                }
                await DuoPreview.transition(to: state, animation: .none)
                await settle(config)
                let image = captureContent(host: host)
                try image.pngData()?.write(to: directory.appendingPathComponent(fileName(index: index, token: token)))
            }
            await DuoPreview.transition(to: original, animation: .none)
            duoPrint("screenshots saved to \(directory.path)")
            return directory
        } catch {
            duoPrint("screenshots failed: \(error)")
            await DuoPreview.transition(to: original, animation: .none)
            return nil
        }
    }
}
