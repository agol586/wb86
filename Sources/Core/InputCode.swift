struct InputCode: Hashable, Comparable, Sendable {
    let letters: String
    let packedValue: UInt32

    init?(_ rawValue: String) {
        let bytes = Array(rawValue.utf8)
        guard (1...4).contains(bytes.count) else { return nil }

        var normalized = [UInt8]()
        normalized.reserveCapacity(bytes.count)
        var packed: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            let lowercase: UInt8
            switch byte {
            case 65...89: lowercase = byte + 32
            case 97...121: lowercase = byte
            default: return nil
            }
            normalized.append(lowercase)
            let value = UInt32(lowercase - 96)
            packed |= value << UInt32((3 - index) * 5)
        }

        letters = String(decoding: normalized, as: UTF8.self)
        packedValue = packed
    }

    init?(packedValue: UInt32, length: Int) {
        guard (1...4).contains(length) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(length)
        for index in 0..<4 {
            let value = UInt8((packedValue >> UInt32((3 - index) * 5)) & 0x1f)
            if index < length {
                guard (1...25).contains(value) else { return nil }
                bytes.append(value + 96)
            } else if value != 0 {
                return nil
            }
        }
        let decoded = String(decoding: bytes, as: UTF8.self)
        guard let validated = InputCode(decoded), validated.packedValue == packedValue else { return nil }
        self = validated
    }

    var length: Int { letters.utf8.count }

    static func < (lhs: InputCode, rhs: InputCode) -> Bool {
        lhs.packedValue < rhs.packedValue
    }
}
