import AppKit
import Foundation

enum ModifierTapState: Equatable {
    case idle
    case eligible(keyCode: UInt16, pressedAt: TimeInterval, settingsGeneration: UInt64)
    case disqualified
}

final class StandaloneShiftRecognizer {
    typealias Clock = () -> TimeInterval

    private static let shiftKeyCodes: Set<UInt16> = [56, 60]
    private static let disallowedModifiers: NSEvent.ModifierFlags = [
        .command, .control, .option, .capsLock, .function
    ]

    private let maximumTapDuration: TimeInterval
    private let clock: Clock
    private var pressedShiftKeys = Set<UInt16>()
    private var observedSettingsGeneration: UInt64?
    private(set) var state = ModifierTapState.idle

    init(maximumTapDuration: TimeInterval = 0.4,
         clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }) {
        precondition(maximumTapDuration > 0)
        self.maximumTapDuration = maximumTapDuration
        self.clock = clock
    }

    /// Returns true only for the release completing one valid standalone Shift tap.
    /// Press and release events themselves remain available for pass-through by the adapter.
    func handle(_ event: NSEvent, settingsGeneration: UInt64) -> Bool {
        if let observedSettingsGeneration,
           observedSettingsGeneration != settingsGeneration {
            reset()
        }
        observedSettingsGeneration = settingsGeneration

        guard event.type == .flagsChanged,
              Self.shiftKeyCodes.contains(event.keyCode) else {
            disqualifyForNonModifierKey()
            return false
        }

        let timestamp = event.timestamp > 0 ? event.timestamp : clock()
        if pressedShiftKeys.contains(event.keyCode) {
            // A lone Shift still present in the aggregate flags cannot be this key's release.
            // Treat the duplicate transition as disqualifying without consulting isARepeat.
            if pressedShiftKeys.count == 1, event.modifierFlags.contains(.shift) {
                state = .disqualified
                return false
            }
            return release(keyCode: event.keyCode, modifiers: event.modifierFlags,
                           timestamp: timestamp, settingsGeneration: settingsGeneration)
        }

        guard event.modifierFlags.contains(.shift) else {
            // An orphan release may arrive after reset, activation or a settings generation change.
            return false
        }
        return press(keyCode: event.keyCode, modifiers: event.modifierFlags,
                     timestamp: timestamp, settingsGeneration: settingsGeneration)
    }

    func disqualifyForNonModifierKey() {
        state = pressedShiftKeys.isEmpty ? .idle : .disqualified
    }

    func reset() {
        pressedShiftKeys.removeAll(keepingCapacity: true)
        observedSettingsGeneration = nil
        state = .idle
    }

    private func press(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                       timestamp: TimeInterval, settingsGeneration: UInt64) -> Bool {
        pressedShiftKeys.insert(keyCode)
        let otherModifiers = modifiers.intersection(Self.disallowedModifiers)
        guard pressedShiftKeys.count == 1, otherModifiers.isEmpty else {
            state = .disqualified
            return false
        }
        state = .eligible(keyCode: keyCode, pressedAt: timestamp,
                          settingsGeneration: settingsGeneration)
        return false
    }

    private func release(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                         timestamp: TimeInterval, settingsGeneration: UInt64) -> Bool {
        pressedShiftKeys.remove(keyCode)
        let triggered: Bool
        if case let .eligible(eligibleKeyCode, pressedAt, eligibleGeneration) = state {
            let duration = timestamp - pressedAt
            triggered = eligibleKeyCode == keyCode
                && eligibleGeneration == settingsGeneration
                && duration >= 0
                && duration <= maximumTapDuration
                && modifiers.intersection(Self.disallowedModifiers).isEmpty
                && pressedShiftKeys.isEmpty
        } else {
            triggered = false
        }
        state = pressedShiftKeys.isEmpty ? .idle : .disqualified
        return triggered
    }
}
