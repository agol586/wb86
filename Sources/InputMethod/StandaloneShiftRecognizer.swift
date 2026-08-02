import AppKit
import Foundation

enum ModifierTapState: Equatable {
    case idle
    case eligible(keyCode: UInt16, pressedAt: TimeInterval, settingsGeneration: UInt64)
    case disqualified
}

final class StandaloneModifierRecognizer {
    typealias Clock = () -> TimeInterval

    private static let relevantModifiers: NSEvent.ModifierFlags = [
        .command, .control, .option, .shift, .capsLock, .function
    ]

    private let maximumTapDuration: TimeInterval
    private let clock: Clock
    private var pressedModifierKeys = Set<UInt16>()
    private var observedSettingsGeneration: UInt64?
    private var observedBinding: ModeSwitchBinding?
    private(set) var state = ModifierTapState.idle

    init(maximumTapDuration: TimeInterval = 0.4,
         clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }) {
        precondition(maximumTapDuration > 0)
        self.maximumTapDuration = maximumTapDuration
        self.clock = clock
    }

    /// Returns true only for the release completing one valid standalone Shift tap.
    /// Press and release events themselves remain available for pass-through by the adapter.
    func handle(_ event: NSEvent, binding: ModeSwitchBinding,
                settingsGeneration: UInt64) -> Bool {
        if let observedSettingsGeneration,
           observedSettingsGeneration != settingsGeneration
            || observedBinding != binding {
            reset()
        }
        observedSettingsGeneration = settingsGeneration
        observedBinding = binding

        guard let definition = ModifierDefinition(binding: binding) else {
            pressedModifierKeys.removeAll(keepingCapacity: true)
            state = .idle
            return false
        }

        guard event.type == .flagsChanged,
              definition.keyCodes.contains(event.keyCode) else {
            disqualifyForNonModifierKey()
            return false
        }

        let timestamp = event.timestamp > 0 ? event.timestamp : clock()
        let otherModifiers = event.modifierFlags
            .intersection(Self.relevantModifiers)
            .subtracting(definition.flag)
        guard otherModifiers.isEmpty else {
            state = .disqualified
            return false
        }

        if definition.isToggle {
            pressedModifierKeys.removeAll(keepingCapacity: true)
            state = .idle
            return true
        }

        if pressedModifierKeys.contains(event.keyCode) {
            // A repeated edge or release while the other side remains held must not trigger.
            if event.modifierFlags.contains(definition.flag) {
                pressedModifierKeys.remove(event.keyCode)
                state = .disqualified
                return false
            }
            return release(keyCode: event.keyCode, modifiers: event.modifierFlags,
                           targetFlag: definition.flag, timestamp: timestamp,
                           settingsGeneration: settingsGeneration)
        }

        guard event.modifierFlags.contains(definition.flag) else {
            // An orphan release may arrive after reset, activation or a settings generation change.
            return false
        }
        return press(keyCode: event.keyCode, modifiers: event.modifierFlags,
                     targetFlag: definition.flag, timestamp: timestamp,
                     settingsGeneration: settingsGeneration)
    }

    func disqualifyForNonModifierKey() {
        state = pressedModifierKeys.isEmpty ? .idle : .disqualified
    }

    func reset() {
        pressedModifierKeys.removeAll(keepingCapacity: true)
        observedSettingsGeneration = nil
        observedBinding = nil
        state = .idle
    }

    private func press(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                       targetFlag: NSEvent.ModifierFlags,
                       timestamp: TimeInterval, settingsGeneration: UInt64) -> Bool {
        pressedModifierKeys.insert(keyCode)
        let otherModifiers = modifiers.intersection(Self.relevantModifiers)
            .subtracting(targetFlag)
        guard pressedModifierKeys.count == 1, otherModifiers.isEmpty else {
            state = .disqualified
            return false
        }
        state = .eligible(keyCode: keyCode, pressedAt: timestamp,
                          settingsGeneration: settingsGeneration)
        return false
    }

    private func release(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                         targetFlag: NSEvent.ModifierFlags,
                         timestamp: TimeInterval, settingsGeneration: UInt64) -> Bool {
        pressedModifierKeys.remove(keyCode)
        let triggered: Bool
        if case let .eligible(eligibleKeyCode, pressedAt, eligibleGeneration) = state {
            let duration = timestamp - pressedAt
            triggered = eligibleKeyCode == keyCode
                && eligibleGeneration == settingsGeneration
                && duration >= 0
                && duration <= maximumTapDuration
                && modifiers.intersection(Self.relevantModifiers)
                    .subtracting(targetFlag).isEmpty
                && pressedModifierKeys.isEmpty
        } else {
            triggered = false
        }
        state = pressedModifierKeys.isEmpty ? .idle : .disqualified
        return triggered
    }

    private struct ModifierDefinition {
        let keyCodes: Set<UInt16>
        let flag: NSEvent.ModifierFlags
        let isToggle: Bool

        init?(binding: ModeSwitchBinding) {
            switch binding {
            case .standaloneShift:
                keyCodes = [56, 60]
                flag = .shift
                isToggle = false
            case .standaloneControl:
                keyCodes = [59, 62]
                flag = .control
                isToggle = false
            case .standaloneCapsLock:
                keyCodes = [57]
                flag = .capsLock
                isToggle = true
            case .controlShiftF, .shiftSpace, .legacyControlShiftDigits, .custom, .disabled:
                return nil
            }
        }
    }
}
