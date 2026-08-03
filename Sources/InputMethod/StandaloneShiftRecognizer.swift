import AppKit
import Foundation

enum ModifierTapState: Equatable {
    case idle
    case eligible(keyCode: UInt16?, pressedAt: TimeInterval, settingsGeneration: UInt64)
    case disqualified
}

final class StandaloneModifierRecognizer {
    typealias Clock = () -> TimeInterval

    private static let relevantModifiers: NSEvent.ModifierFlags = [
        .command, .control, .option, .shift, .capsLock, .function
    ]
    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63
    ]

    private let maximumTapDuration: TimeInterval
    private let clock: Clock
    private var lastModifierFlags: NSEvent.ModifierFlags?
    private var observedSettingsGeneration: UInt64?
    private var observedBinding: ModeSwitchBinding?
    private(set) var state = ModifierTapState.idle

    init(maximumTapDuration: TimeInterval = 0.4,
         clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }) {
        precondition(maximumTapDuration > 0)
        self.maximumTapDuration = maximumTapDuration
        self.clock = clock
    }

    /// Returns true only for the release completing one valid standalone modifier tap.
    /// Press and release events remain available for pass-through by the adapter.
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
            state = .idle
            return false
        }

        guard event.type == .flagsChanged else {
            disqualifyForNonModifierKey()
            return false
        }

        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        let previousModifiers = lastModifierFlags ?? []
        let changedModifiers = previousModifiers.symmetricDifference(modifiers)
        lastModifierFlags = modifiers

        // Some IMK clients (observed with physical Shift in VS Code) deliver each
        // flagsChanged edge twice. An identical aggregate state is an idempotent
        // replay, not a second physical transition. Preserve the pending gesture;
        // a duplicated release after completion must likewise remain idle.
        guard !changedModifiers.isEmpty else { return false }

        let hasExactTargetKeyCode = definition.keyCodes.contains(event.keyCode)
        let keyCode: UInt16?
        if hasExactTargetKeyCode {
            keyCode = event.keyCode
        } else if !Self.modifierKeyCodes.contains(event.keyCode),
                  changedModifiers == definition.flag {
            // Some InputMethodKit clients and remote-input bridges deliver a valid
            // flagsChanged edge with keyCode 0. The aggregate transition still
            // identifies one configured modifier without global event monitoring.
            keyCode = nil
        } else {
            // A completed unrelated modifier gesture (for example Command-Tab or
            // Command-L) must not poison the next standalone Shift tap. Keep a
            // pending target gesture disqualified while its flag is still down,
            // then return to idle once the target is absent.
            state = modifiers.contains(definition.flag) ? .disqualified : .idle
            return false
        }

        let isExactPressResynchronizingStaleReleasedFlags = hasExactTargetKeyCode
            && modifiers == definition.flag
            && !previousModifiers.contains(definition.flag)
        guard changedModifiers == definition.flag
                || isExactPressResynchronizingStaleReleasedFlags else {
            state = .disqualified
            return false
        }

        let timestamp = event.timestamp > 0 ? event.timestamp : clock()
        let otherModifiers = modifiers.subtracting(definition.flag)
        guard otherModifiers.isEmpty else {
            state = .disqualified
            return false
        }

        if definition.isToggle {
            state = .idle
            return true
        }

        if modifiers.contains(definition.flag) {
            guard state == .idle else {
                state = .disqualified
                return false
            }
            state = .eligible(keyCode: keyCode, pressedAt: timestamp,
                              settingsGeneration: settingsGeneration)
            return false
        }

        return release(keyCode: keyCode, timestamp: timestamp,
                       settingsGeneration: settingsGeneration)
    }

    func disqualifyForNonModifierKey() {
        if state != .idle { state = .disqualified }
    }

    /// Preserve the last aggregate flags across an ordinary IMK lifecycle boundary,
    /// while ensuring a press started before that boundary can never complete a tap.
    func suspend() {
        if state != .idle { state = .disqualified }
    }

    func reset() {
        lastModifierFlags = nil
        observedSettingsGeneration = nil
        observedBinding = nil
        state = .idle
    }

    private func release(keyCode: UInt16?, timestamp: TimeInterval,
                         settingsGeneration: UInt64) -> Bool {
        let triggered: Bool
        if case let .eligible(eligibleKeyCode, pressedAt, eligibleGeneration) = state {
            let duration = timestamp - pressedAt
            let physicalKeyMatches = eligibleKeyCode == nil
                || keyCode == nil
                || eligibleKeyCode == keyCode
            triggered = physicalKeyMatches
                && eligibleGeneration == settingsGeneration
                && duration >= 0
                && duration <= maximumTapDuration
        } else {
            triggered = false
        }
        state = .idle
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
