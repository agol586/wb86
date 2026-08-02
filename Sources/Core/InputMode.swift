enum InputLanguage: String, Codable, Sendable {
    case chinese
    case directEnglish
}

enum PunctuationMode: String, Codable, Sendable {
    case chinese
    case english
}

enum CharacterWidth: String, Codable, Sendable {
    case half
    case full
}

enum OutputScript: String, Codable, Sendable {
    case simplified
    case traditional
}

struct InputMode: Equatable, Codable, Sendable {
    var language: InputLanguage
    var punctuation: PunctuationMode
    var width: CharacterWidth
    var script: OutputScript

    static let `default` = InputMode(
        language: .chinese,
        punctuation: .chinese,
        width: .half,
        script: .simplified
    )

    /// Chinese punctuation is meaningful only while the session is in Chinese
    /// input. Width conversion remains available in either language mode.
    var effectivePunctuation: PunctuationMode {
        language == .chinese ? punctuation : .english
    }
}
