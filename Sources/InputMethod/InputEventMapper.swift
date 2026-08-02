import AppKit

enum InputEventMapper {
    static func map(_ event: NSEvent, isComposing: Bool,
                    keyBindings: KeyBindingSettings = .default,
                    candidate2And3ShortcutsEnabled: Bool = false) -> InputEvent {
        map(event, resolvedCharacters: event.charactersIgnoringModifiers,
            isComposing: isComposing, keyBindings: keyBindings,
            candidate2And3ShortcutsEnabled: candidate2And3ShortcutsEnabled)
    }

    static func map(_ event: NSEvent, translatedCharacter: String?, isComposing: Bool,
                    keyBindings: KeyBindingSettings,
                    candidate2And3ShortcutsEnabled: Bool) -> InputEvent {
        map(event, resolvedCharacters: translatedCharacter,
            isComposing: isComposing, keyBindings: keyBindings,
            candidate2And3ShortcutsEnabled: candidate2And3ShortcutsEnabled)
    }

    private static func map(_ event: NSEvent, resolvedCharacters: String?, isComposing: Bool,
                            keyBindings: KeyBindingSettings,
                            candidate2And3ShortcutsEnabled: Bool) -> InputEvent {
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
        if isComposing {
            if candidate2And3ShortcutsEnabled, exactModeFlags.isEmpty {
                switch event.keyCode {
                case 41: return .select(2)
                case 39: return .select(3)
                default: break
                }
            }
            if let page = pageEvent(for: event, groups: keyBindings.pageKeyGroups,
                                    flags: exactModeFlags) {
                return page
            }
            if isCandidateControlKey(event.keyCode), !exactModeFlags.isEmpty {
                return .passThrough
            }
        }
        guard let characters = resolvedCharacters, characters.count == 1 else {
            return .passThrough
        }
        switch characters {
        case " " where isComposing && exactModeFlags.isEmpty: return .selectFirst
        case "1"..."9" where isComposing && exactModeFlags.isEmpty:
            return .select(Int(characters) ?? 0)
        default:
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
        case .standaloneShift, .standaloneControl, .standaloneCapsLock,
             .legacyControlShiftDigits, .custom, .disabled:
            return false
        }
    }

    private static func pageEvent(for event: NSEvent, groups: Set<CandidatePageKeyGroup>,
                                  flags: NSEvent.ModifierFlags) -> InputEvent? {
        if groups.contains(.tab), event.keyCode == 48 {
            if flags == [.shift] { return .pagePrevious }
            if flags.isEmpty { return .pageNext }
            return nil
        }
        guard flags.isEmpty else { return nil }
        switch event.keyCode {
        case 43 where groups.contains(.commaPeriod),
             27 where groups.contains(.minusEquals),
             33 where groups.contains(.bracketPair),
             126 where groups.contains(.arrows):
            return .pagePrevious
        case 47 where groups.contains(.commaPeriod),
             24 where groups.contains(.minusEquals),
             30 where groups.contains(.bracketPair),
             125 where groups.contains(.arrows):
            return .pageNext
        default: return nil
        }
    }

    private static func isCandidateControlKey(_ keyCode: UInt16) -> Bool {
        [18, 19, 20, 21, 22, 23, 25, 26, 28, 29, 39, 41, 43, 47,
         27, 24, 33, 30, 48, 49, 125, 126].contains(keyCode)
    }
}
