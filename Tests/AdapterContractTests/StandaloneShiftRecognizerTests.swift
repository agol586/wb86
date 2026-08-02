import AppKit
import XCTest
@testable import MacWubi

final class StandaloneShiftRecognizerTests: XCTestCase {
    func testLeftAndRightShiftOrControlTapTriggerExactlyOnceOnRelease() throws {
        let cases: [(ModeSwitchBinding, [UInt16], NSEvent.ModifierFlags)] = [
            (.standaloneShift, [56, 60], .shift),
            (.standaloneControl, [59, 62], .control)
        ]
        for (binding, keyCodes, flag) in cases {
            for keyCode in keyCodes {
                let recognizer = StandaloneModifierRecognizer(maximumTapDuration: 0.4)
            XCTAssertFalse(recognizer.handle(
                try flagsEvent(keyCode: keyCode, flags: flag, timestamp: 10),
                binding: binding,
                settingsGeneration: 1
            ))
            XCTAssertTrue(recognizer.handle(
                try flagsEvent(keyCode: keyCode, flags: [], timestamp: 10.2),
                binding: binding,
                settingsGeneration: 1
            ))
            XCTAssertEqual(recognizer.state, .idle)
            }
        }
    }

    func testCapsLockToggleEventTriggersOnceAndDisabledNeverTriggers() throws {
        let recognizer = StandaloneModifierRecognizer(maximumTapDuration: 0.4)
        XCTAssertTrue(recognizer.handle(
            try flagsEvent(keyCode: 57, flags: [.capsLock], timestamp: 1),
            binding: .standaloneCapsLock,
            settingsGeneration: 1
        ))
        XCTAssertTrue(recognizer.handle(
            try flagsEvent(keyCode: 57, flags: [], timestamp: 2),
            binding: .standaloneCapsLock,
            settingsGeneration: 1
        ))
        XCTAssertFalse(recognizer.handle(
            try flagsEvent(keyCode: 57, flags: [.capsLock], timestamp: 3),
            binding: .disabled,
            settingsGeneration: 1
        ))
    }

    func testLongPressAndRepeatedFlagsChangedDoNotTrigger() throws {
        let recognizer = StandaloneModifierRecognizer(maximumTapDuration: 0.4)
        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1),
                              binding: .standaloneShift,
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 1.5),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 2),
                              binding: .standaloneShift,
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(
            try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 2.1, isARepeat: true),
            binding: .standaloneShift,
            settingsGeneration: 1
        ))
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 2.2),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))
    }

    func testSecondShiftAndOtherModifiersDisqualifyGesture() throws {
        let recognizer = StandaloneModifierRecognizer(maximumTapDuration: 0.4)
        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1),
                              binding: .standaloneShift,
                              settingsGeneration: 1)
        _ = recognizer.handle(try flagsEvent(keyCode: 60, flags: [.shift], timestamp: 1.1),
                              binding: .standaloneShift,
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1.2),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 60, flags: [], timestamp: 1.3),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift, .control],
                                             timestamp: 2), binding: .standaloneShift,
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 2.1),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))
    }

    func testOtherKeyResetAndIsolatedReleaseHaveNoSideEffect() throws {
        let recognizer = StandaloneModifierRecognizer(maximumTapDuration: 0.4)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 1),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 2),
                              binding: .standaloneShift,
                              settingsGeneration: 1)
        recognizer.disqualifyForNonModifierKey()
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 2.1),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 3),
                              binding: .standaloneShift,
                              settingsGeneration: 1)
        recognizer.reset()
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 3.1),
                                         binding: .standaloneShift,
                                         settingsGeneration: 1))
    }

    func testSettingsGenerationChangeInvalidatesPendingTap() throws {
        let recognizer = StandaloneModifierRecognizer(maximumTapDuration: 0.4)
        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1),
                              binding: .standaloneShift,
                              settingsGeneration: 4)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 1.1),
                                         binding: .standaloneShift,
                                         settingsGeneration: 5))

        _ = recognizer.handle(try flagsEvent(keyCode: 59, flags: [.control], timestamp: 2),
                              binding: .standaloneControl,
                              settingsGeneration: 5)
        XCTAssertTrue(recognizer.handle(try flagsEvent(keyCode: 59, flags: [], timestamp: 2.1),
                                        binding: .standaloneControl,
                                        settingsGeneration: 5))
    }

    private func flagsEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags,
                            timestamp: TimeInterval, isARepeat: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }
}
