struct PunctuationConverter: Sendable {
    private var nextDoubleQuoteIsOpening = true
    private var nextSingleQuoteIsOpening = true

    mutating func convert(_ text: String, mode: InputMode) -> String? {
        convert(text, punctuation: mode.effectivePunctuation, width: mode.width)
    }

    mutating func convert(_ text: String,
                          punctuation: PunctuationMode,
                          width: CharacterWidth) -> String? {
        guard text.count == 1, let scalar = text.unicodeScalars.first,
              text.unicodeScalars.count == 1 else {
            return nil
        }

        if punctuation == .chinese {
            if text == "\"" {
                defer { nextDoubleQuoteIsOpening.toggle() }
                return nextDoubleQuoteIsOpening ? "“" : "”"
            }
            if text == "'" {
                defer { nextSingleQuoteIsOpening.toggle() }
                return nextSingleQuoteIsOpening ? "‘" : "’"
            }
            if let converted = Self.chinesePunctuation[text] {
                return converted
            }
        }

        guard width == .full else { return nil }
        if scalar.value == 0x20 { return "　" }
        guard (0x21...0x7e).contains(scalar.value),
              let converted = UnicodeScalar(scalar.value + 0xfee0) else {
            return nil
        }
        return String(converted)
    }

    private static let chinesePunctuation: [String: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！",
        ":": "：", ";": "；", "\\": "、",
        "(": "（", ")": "）", "[": "【", "]": "】",
        "{": "｛", "}": "｝", "<": "《", ">": "》"
    ]
}
