import Foundation

enum CandidateLayout: String, Codable, CaseIterable, Sendable {
    case vertical
    case horizontal
}

enum SettingsValidationError: Error, Equatable {
    case invalidPageSize
    case invalidFontScale
    case unsupportedSchema
    case corruptPayload
}

struct InputSettings: Equatable, Codable, Sendable {
    static let schemaVersion: UInt32 = 2

    var candidatePageSize: Int
    var candidateLayout: CandidateLayout
    var candidateFontScale: Double
    var keyBindings: KeyBindingSettings
    var autoCommitAtFour: Bool
    var autoCommitFirstAtFive: Bool
    var defaultMode: InputMode
    var automaticFrequency: Bool
    var mixedPinyinEnabled: Bool
    var codeHintEnabled: Bool
    var candidate2And3ShortcutsEnabled: Bool

    /// Defaults shown to a new install and restored by the explicit Reset action.
    static let newInstallDefault = try! InputSettings(
        candidatePageSize: 5,
        candidateLayout: .vertical,
        candidateFontScale: 1,
        keyBindings: .default,
        autoCommitAtFour: true,
        autoCommitFirstAtFive: false,
        defaultMode: InputMode(language: .chinese, punctuation: .english,
                               width: .half, script: .simplified),
        automaticFrequency: false,
        mixedPinyinEnabled: true,
        codeHintEnabled: true,
        candidate2And3ShortcutsEnabled: false
    )

    /// Conservative values used only when schema-v1 data is migrated.
    static let migrationCompatibilityDefault = try! InputSettings(
        candidatePageSize: 5,
        candidateLayout: .vertical,
        candidateFontScale: 1,
        keyBindings: .default,
        autoCommitAtFour: false,
        autoCommitFirstAtFive: false,
        defaultMode: .default,
        automaticFrequency: true,
        mixedPinyinEnabled: false,
        codeHintEnabled: false,
        candidate2And3ShortcutsEnabled: false
    )

    static let `default` = newInstallDefault

    init(candidatePageSize: Int = 5, candidateLayout: CandidateLayout = .vertical,
         candidateFontScale: Double = 1, keyBindings: KeyBindingSettings = .default,
         autoCommitAtFour: Bool = true, autoCommitFirstAtFive: Bool = false,
         defaultMode: InputMode = InputMode(language: .chinese, punctuation: .english,
                                            width: .half, script: .simplified),
         automaticFrequency: Bool = false, mixedPinyinEnabled: Bool = true,
         codeHintEnabled: Bool = true,
         candidate2And3ShortcutsEnabled: Bool = false) throws {
        guard (5...9).contains(candidatePageSize) else {
            throw SettingsValidationError.invalidPageSize
        }
        guard (0.8...2).contains(candidateFontScale), candidateFontScale.isFinite else {
            throw SettingsValidationError.invalidFontScale
        }
        self.candidatePageSize = candidatePageSize
        self.candidateLayout = candidateLayout
        self.candidateFontScale = candidateFontScale
        self.keyBindings = keyBindings
        self.autoCommitAtFour = autoCommitAtFour
        self.autoCommitFirstAtFive = autoCommitFirstAtFive
        self.defaultMode = defaultMode
        self.automaticFrequency = automaticFrequency
        self.mixedPinyinEnabled = mixedPinyinEnabled
        self.codeHintEnabled = codeHintEnabled
        self.candidate2And3ShortcutsEnabled = candidate2And3ShortcutsEnabled
    }

    init(candidatePageSize: Int = 5, candidateLayout: CandidateLayout = .vertical,
         candidateFontScale: Double = 1, keyBindings: KeyBindingSettings = .default,
         autoCommitAtFour: Bool = true,
         defaultMode: InputMode = InputMode(language: .chinese, punctuation: .english,
                                            width: .half, script: .simplified),
         learningEnabled: Bool) throws {
        try self.init(candidatePageSize: candidatePageSize,
                      candidateLayout: candidateLayout,
                      candidateFontScale: candidateFontScale,
                      keyBindings: keyBindings,
                      autoCommitAtFour: autoCommitAtFour,
                      autoCommitFirstAtFive: false,
                      defaultMode: defaultMode,
                      automaticFrequency: learningEnabled,
                      mixedPinyinEnabled: true,
                      codeHintEnabled: true,
                      candidate2And3ShortcutsEnabled: false)
    }

    /// Source-compatible name for existing runtime policy call sites.
    var learningEnabled: Bool {
        get { automaticFrequency }
        set { automaticFrequency = newValue }
    }

    func validated() throws -> InputSettings {
        try InputSettings(candidatePageSize: candidatePageSize,
                          candidateLayout: candidateLayout,
                          candidateFontScale: candidateFontScale,
                          keyBindings: keyBindings,
                          autoCommitAtFour: autoCommitAtFour,
                          autoCommitFirstAtFive: autoCommitFirstAtFive,
                          defaultMode: defaultMode,
                          automaticFrequency: automaticFrequency,
                          mixedPinyinEnabled: mixedPinyinEnabled,
                          codeHintEnabled: codeHintEnabled,
                          candidate2And3ShortcutsEnabled: candidate2And3ShortcutsEnabled)
    }
}

final class SettingsStore {
    private let writer: SnapshotWriter
    private(set) var generation: UInt64 = 0
    private(set) var settings = InputSettings.default

    init(writer: SnapshotWriter) throws {
        self.writer = writer
        if let snapshot = try writer.recover(.settings,
                                             supportedSchemaVersions: [InputSettings.schemaVersion]) {
            guard let decoded = try? JSONDecoder().decode(InputSettings.self,
                                                          from: snapshot.payload) else {
                throw SettingsValidationError.corruptPayload
            }
            settings = try decoded.validated()
            generation = snapshot.generation
        }
    }

    func save(_ value: InputSettings) throws {
        let validated = try value.validated()
        let nextGeneration = generation + 1
        let payload = try JSONEncoder.sorted.encode(validated)
        try writer.commit(try DataSnapshot(domain: .settings,
                                           schemaVersion: InputSettings.schemaVersion,
                                           generation: nextGeneration, payload: payload)) {
            (try? JSONDecoder().decode(InputSettings.self, from: $0).validated()) != nil
        }
        settings = validated
        generation = nextGeneration
    }

    func restoreDefaults() throws { try save(.default) }
}
