import UIKit

/// Keyboard shortcuts shared by the host and the HUD window.
@MainActor
enum DuoKeyCommands {
    private enum Action: String {
        case preset, fold, angleDown, angleUp, cycleAnimation, screenshots, toggleHUD
    }

    static func commands(config: DuoConfiguration) -> [UIKeyCommand] {
        var result: [UIKeyCommand] = []
        for (index, preset) in config.presets.prefix(9).enumerated() {
            result.append(make("\(index + 1)", [.command], .preset, "Duo: \(preset.displayTitle)", index: index))
        }
        result.append(make("f", [.command], .fold, "Duo: Fold / Unfold"))
        result.append(make(UIKeyCommand.inputLeftArrow, [.command], .angleDown, "Duo: Angle −"))
        result.append(make(UIKeyCommand.inputRightArrow, [.command], .angleUp, "Duo: Angle +"))
        result.append(make("a", [.command, .shift], .cycleAnimation, "Duo: Next Animation Mode"))
        result.append(make("s", [.command, .shift], .screenshots, "Duo: Screenshot All States"))
        result.append(make("d", [.command, .shift], .toggleHUD, "Duo: Toggle Panel"))
        return result
    }

    static func perform(_ command: UIKeyCommand, runtime: DuoRuntime) {
        guard let info = command.propertyList as? [String: Any],
              let raw = info["action"] as? String, let action = Action(rawValue: raw) else { return }
        switch action {
        case .preset: runtime.selectPreset(at: info["index"] as? Int ?? 0)
        case .fold: runtime.toggleFold()
        case .angleDown: runtime.stepAngle(by: -runtime.config.angles.keyboardStep)
        case .angleUp: runtime.stepAngle(by: runtime.config.angles.keyboardStep)
        case .cycleAnimation: runtime.cycleAnimation()
        case .screenshots: Task { await DuoPreview.captureAllStates() }
        case .toggleHUD: runtime.toggleHUD()
        }
    }

    private static func make(_ input: String, _ flags: UIKeyModifierFlags, _ action: Action, _ title: String,
                             index: Int = 0) -> UIKeyCommand {
        let command = UIKeyCommand(title: title, action: #selector(DuoHostViewController.duoHandleKeyCommand(_:)),
                                   input: input, modifierFlags: flags,
                                   propertyList: ["action": action.rawValue, "index": index])
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}
