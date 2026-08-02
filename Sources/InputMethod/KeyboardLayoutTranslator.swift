import AppKit
import Carbon
import Foundation

enum KeyboardLayoutTranslation: Equatable {
    case character(String)
    case deadKey
    case unavailable
}

protocol KeyboardLayoutSnapshot {
    var identifier: String { get }
    func translate(keyCode: UInt16,
                   modifiers: NSEvent.ModifierFlags) -> KeyboardLayoutTranslation
}

final class KeyboardLayoutTranslator {
    typealias SystemSnapshotProvider = () -> (any KeyboardLayoutSnapshot)?

    private let systemSnapshotProvider: SystemSnapshotProvider

    init(systemSnapshotProvider: @escaping SystemSnapshotProvider = {
        CurrentASCIIKeyboardLayout.snapshot()
    }) {
        self.systemSnapshotProvider = systemSnapshotProvider
    }

    func character(for event: NSEvent, layout: KeyboardLayoutSelection) -> String? {
        character(keyCode: event.keyCode, modifiers: event.modifierFlags, layout: layout)
    }

    func character(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                   layout: KeyboardLayoutSelection) -> String? {
        switch layout {
        case .us:
            return ANSIUSKeyboardLayout.character(keyCode: keyCode, modifiers: modifiers)
        case .followSystem:
            guard let snapshot = systemSnapshotProvider() else { return nil }
            return validatedASCII(snapshot.translate(keyCode: keyCode, modifiers: modifiers))
        }
    }

    private func validatedASCII(_ translation: KeyboardLayoutTranslation) -> String? {
        guard case let .character(character) = translation,
              character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.isASCII,
              (0x20...0x7e).contains(scalar.value) else { return nil }
        return character
    }
}

private enum ANSIUSKeyboardLayout {
    private static let unshifted: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 49: " ", 50: "`"
    ]

    private static let shifted: [Character: Character] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^",
        "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
        "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<",
        ".": ">", "/": "?", "`": "~"
    ]

    static func character(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        guard let base = unshifted[keyCode] else { return nil }
        guard modifiers.contains(.shift) else { return String(base) }
        if base.isLetter { return String(base).uppercased() }
        return String(shifted[base] ?? base)
    }
}

private enum CurrentASCIIKeyboardLayout {
    static func snapshot() -> (any KeyboardLayoutSnapshot)? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source,
                                                      kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let cfData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
        return CarbonKeyboardLayoutSnapshot(
            identifier: "ascii-capable-layout",
            layoutData: Data(referencing: cfData as NSData)
        )
    }
}

private struct CarbonKeyboardLayoutSnapshot: KeyboardLayoutSnapshot {
    let identifier: String
    let layoutData: Data

    func translate(keyCode: UInt16,
                   modifiers: NSEvent.ModifierFlags) -> KeyboardLayoutTranslation {
        layoutData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return .unavailable }
            let layout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                carbonModifierState(modifiers),
                UInt32(LMGetKbdType()),
                OptionBits(0),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr else { return .unavailable }
            if length == 0, deadKeyState != 0 { return .deadKey }
            guard length > 0, length <= characters.count else { return .unavailable }
            return .character(String(utf16CodeUnits: characters, count: length))
        }
    }

    private func carbonModifierState(_ modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var state = 0
        if modifiers.contains(.shift) { state |= shiftKey }
        if modifiers.contains(.control) { state |= controlKey }
        if modifiers.contains(.option) { state |= optionKey }
        if modifiers.contains(.command) { state |= cmdKey }
        return UInt32((state >> 8) & 0xff)
    }
}
