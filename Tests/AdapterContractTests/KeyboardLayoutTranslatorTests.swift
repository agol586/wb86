import AppKit
import XCTest
@testable import MacWubi

final class KeyboardLayoutTranslatorTests: XCTestCase {
    func testFixedANSIUSIgnoresActiveQwertyAndDvorakLayouts() {
        let provider = SwitchingKeyboardSnapshotProvider([
            StubKeyboardSnapshot(identifier: "qwerty", values: [12: .character("q")]),
            StubKeyboardSnapshot(identifier: "dvorak", values: [12: .character("'")])
        ])
        let translator = KeyboardLayoutTranslator(systemSnapshotProvider: provider.snapshot)

        XCTAssertEqual(translator.character(keyCode: 12, modifiers: [], layout: .us), "q")
        XCTAssertEqual(translator.character(keyCode: 12, modifiers: [.shift], layout: .us), "Q")
        XCTAssertEqual(provider.snapshotCount, 0)
    }

    func testFollowSystemUsesOneImmutableSnapshotPerEvent() {
        let provider = SwitchingKeyboardSnapshotProvider([
            StubKeyboardSnapshot(identifier: "qwerty", values: [12: .character("q")]),
            StubKeyboardSnapshot(identifier: "dvorak", values: [12: .character("'")])
        ])
        let translator = KeyboardLayoutTranslator(systemSnapshotProvider: provider.snapshot)

        XCTAssertEqual(translator.character(keyCode: 12, modifiers: [],
                                            layout: .followSystem), "q")
        XCTAssertEqual(provider.snapshotCount, 1)
        XCTAssertEqual(translator.character(keyCode: 12, modifiers: [],
                                            layout: .followSystem), "'")
        XCTAssertEqual(provider.snapshotCount, 2)
    }

    func testDeadKeyNilMultiScalarAndNonASCIITranslationsFailClosed() {
        let snapshots = [
            StubKeyboardSnapshot(identifier: "dead", values: [14: .deadKey]),
            StubKeyboardSnapshot(identifier: "missing", values: [:]),
            StubKeyboardSnapshot(identifier: "multi", values: [14: .character("ab")]),
            StubKeyboardSnapshot(identifier: "unicode", values: [14: .character("é")])
        ]
        let provider = SwitchingKeyboardSnapshotProvider(snapshots)
        let translator = KeyboardLayoutTranslator(systemSnapshotProvider: provider.snapshot)

        for _ in snapshots {
            XCTAssertNil(translator.character(keyCode: 14, modifiers: [],
                                              layout: .followSystem))
        }
        XCTAssertNil(KeyboardLayoutTranslator(systemSnapshotProvider: { nil })
            .character(keyCode: 14, modifiers: [], layout: .followSystem))
    }

    func testFixedANSIUSMapsDocumentedLettersDigitsPunctuationAndRejectsUnknownKeys() {
        let translator = KeyboardLayoutTranslator(systemSnapshotProvider: { nil })
        XCTAssertEqual(translator.character(keyCode: 0, modifiers: [], layout: .us), "a")
        XCTAssertEqual(translator.character(keyCode: 18, modifiers: [.shift], layout: .us), "!")
        XCTAssertEqual(translator.character(keyCode: 43, modifiers: [], layout: .us), ",")
        XCTAssertEqual(translator.character(keyCode: 43, modifiers: [.shift], layout: .us), "<")
        XCTAssertNil(translator.character(keyCode: UInt16.max, modifiers: [], layout: .us))
    }
}

private struct StubKeyboardSnapshot: KeyboardLayoutSnapshot {
    let identifier: String
    let values: [UInt16: KeyboardLayoutTranslation]

    func translate(keyCode: UInt16,
                   modifiers: NSEvent.ModifierFlags) -> KeyboardLayoutTranslation {
        values[keyCode] ?? .unavailable
    }
}

private final class SwitchingKeyboardSnapshotProvider {
    private var snapshots: [StubKeyboardSnapshot]
    private(set) var snapshotCount = 0

    init(_ snapshots: [StubKeyboardSnapshot]) { self.snapshots = snapshots }

    func snapshot() -> (any KeyboardLayoutSnapshot)? {
        snapshotCount += 1
        guard !snapshots.isEmpty else { return nil }
        return snapshots.removeFirst()
    }
}
