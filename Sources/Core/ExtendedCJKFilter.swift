import Foundation

/// Mirrors librime's `charset_filter` ranges without depending on host font availability.
enum ExtendedCJKFilter {
    static func permits(_ text: String) -> Bool {
        !text.unicodeScalars.contains(where: isExtendedCJK)
    }

    private static func isExtendedCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,      // Extension A
             0x20000...0x2A6DF,   // Extension B
             0x2A700...0x2B73F,   // Extension C
             0x2B740...0x2B81F,   // Extension D
             0x2B820...0x2CEAF,   // Extension E
             0x2CEB0...0x2EBEF,   // Extension F
             0x30000...0x3134F,   // Extension G
             0x31350...0x323AF,   // Extension H
             0x2EBF0...0x2EE5F,   // Extension I
             0x323B0...0x3347F,   // Extension J
             0xF900...0xFAFF,     // CJK Compatibility Ideographs
             0x2F800...0x2FA1F:  // CJK Compatibility Ideographs Supplement
            return true
        default:
            return false
        }
    }
}
