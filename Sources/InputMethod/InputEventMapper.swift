import AppKit

enum InputEventMapper {
    static func map(_ event: NSEvent, isComposing: Bool,
                    keyBindings: KeyBindingSettings = .default) -> InputEvent {
        guard event.type == .keyDown else { return .passThrough }
        let exactModeFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if !event.isARepeat {
            if usesLegacyDigitBindings(keyBindings), exactModeFlags == [.control, .shift] {
                switch event.keyCode {
                case 18: return .switchLanguage
                case 19: return .switchPunctuation
                case 20: return .switchWidth
                case 21: return .switchScript
                default: break
                }
            }
            if matches(keyBindings.languageSwitch, event: event, flags: exactModeFlags) {
                return .switchLanguage
            }
            if matches(keyBindings.scriptSwitch, event: event, flags: exactModeFlags) {
                return .switchScript
            }
            if matches(keyBindings.widthSwitch, event: event, flags: exactModeFlags) {
                return .switchWidth
            }
        }
        let shortcutFlags = event.modifierFlags.intersection([.command, .control, .option])
        guard shortcutFlags.isEmpty else { return .passThrough }

        switch event.keyCode {
        case 53: return .cancel
        case 51, 117: return .backspace
        default: break
        }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
            return .passThrough
        }
        switch characters {
        case " " where isComposing: return .selectFirst
        case "1"..."9" where isComposing: return .select(Int(characters) ?? 0)
        default:
            if isComposing, let page = pageEvent(for: characters, keySet: keyBindings.pageKeys) {
                return page
            }
            return InputCode(characters) != nil ? .letter(characters) : .text(characters)
        }
    }

    private static func usesLegacyDigitBindings(_ settings: KeyBindingSettings) -> Bool {
        settings.languageSwitch == .legacyControlShiftDigits
            || settings.scriptSwitch == .legacyControlShiftDigits
            || settings.widthSwitch == .legacyControlShiftDigits
    }

    private static func matches(_ binding: ModeSwitchBinding, event: NSEvent,
                                flags: NSEvent.ModifierFlags) -> Bool {
        switch binding {
        case .controlShiftF:
            return event.keyCode == 3 && flags == [.control, .shift]
        case .shiftSpace:
            return event.keyCode == 49 && flags == [.shift]
        case .standaloneShift, .legacyControlShiftDigits, .custom, .disabled:
            return false
        }
    }

    private static func pageEvent(for characters: String,
                                  keySet: CandidatePageKeySet) -> InputEvent? {
        switch (keySet, characters) {
        case (.minusEquals, "-"), (.commaPeriod, ","), (.bracketPair, "["):
            return .pagePrevious
        case (.minusEquals, "="), (.commaPeriod, "."), (.bracketPair, "]"):
            return .pageNext
        default:
            return nil
        }
    }
}
