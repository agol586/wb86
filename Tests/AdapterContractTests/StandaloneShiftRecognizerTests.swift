import AppKit
import XCTest
@testable import MacWubi

final class StandaloneShiftRecognizerTests: XCTestCase {
    func testLeftAndRightShiftTapTriggerExactlyOnceOnRelease() throws {
        for keyCode: UInt16 in [56, 60] {
            let recognizer = StandaloneShiftRecognizer(maximumTapDuration: 0.4)
            XCTAssertFalse(recognizer.handle(
                try flagsEvent(keyCode: keyCode, flags: [.shift], timestamp: 10),
                settingsGeneration: 1
            ))
            XCTAssertTrue(recognizer.handle(
                try flagsEvent(keyCode: keyCode, flags: [], timestamp: 10.2),
                settingsGeneration: 1
            ))
            XCTAssertEqual(recognizer.state, .idle)
        }
    }

    func testLongPressAndRepeatedFlagsChangedDoNotTrigger() throws {
        let recognizer = StandaloneShiftRecognizer(maximumTapDuration: 0.4)
        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1),
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 1.5),
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 2),
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(
            try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 2.1, isARepeat: true),
            settingsGeneration: 1
        ))
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 2.2),
                                         settingsGeneration: 1))
    }

    func testSecondShiftAndOtherModifiersDisqualifyGesture() throws {
        let recognizer = StandaloneShiftRecognizer(maximumTapDuration: 0.4)
        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1),
                              settingsGeneration: 1)
        _ = recognizer.handle(try flagsEvent(keyCode: 60, flags: [.shift], timestamp: 1.1),
                              settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1.2),
                                         settingsGeneration: 1))
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 60, flags: [], timestamp: 1.3),
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift, .control],
                                             timestamp: 2), settingsGeneration: 1)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 2.1),
                                         settingsGeneration: 1))
    }

    func testOtherKeyResetAndIsolatedReleaseHaveNoSideEffect() throws {
        let recognizer = StandaloneShiftRecognizer(maximumTapDuration: 0.4)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 1),
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 2),
                              settingsGeneration: 1)
        recognizer.disqualifyForNonModifierKey()
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 2.1),
                                         settingsGeneration: 1))

        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 3),
                              settingsGeneration: 1)
        recognizer.reset()
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 3.1),
                                         settingsGeneration: 1))
    }

    func testSettingsGenerationChangeInvalidatesPendingTap() throws {
        let recognizer = StandaloneShiftRecognizer(maximumTapDuration: 0.4)
        _ = recognizer.handle(try flagsEvent(keyCode: 56, flags: [.shift], timestamp: 1),
                              settingsGeneration: 4)
        XCTAssertFalse(recognizer.handle(try flagsEvent(keyCode: 56, flags: [], timestamp: 1.1),
                                         settingsGeneration: 5))

        _ = recognizer.handle(try flagsEvent(keyCode: 60, flags: [.shift], timestamp: 2),
                              settingsGeneration: 5)
        XCTAssertTrue(recognizer.handle(try flagsEvent(keyCode: 60, flags: [], timestamp: 2.1),
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
