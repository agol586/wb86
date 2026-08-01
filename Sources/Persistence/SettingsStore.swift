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
    static let schemaVersion: UInt32 = 1

    var candidatePageSize: Int
    var candidateLayout: CandidateLayout
    var candidateFontScale: Double
    var keyBindings: KeyBindingSettings
    var autoCommitAtFour: Bool
    var defaultMode: InputMode
    var learningEnabled: Bool

    static let `default` = try! InputSettings()

    init(candidatePageSize: Int = 5, candidateLayout: CandidateLayout = .vertical,
         candidateFontScale: Double = 1, keyBindings: KeyBindingSettings = .default,
         autoCommitAtFour: Bool = false, defaultMode: InputMode = .default,
         learningEnabled: Bool = true) throws {
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
        self.defaultMode = defaultMode
        self.learningEnabled = learningEnabled
    }

    func validated() throws -> InputSettings {
        try InputSettings(candidatePageSize: candidatePageSize,
                          candidateLayout: candidateLayout,
                          candidateFontScale: candidateFontScale,
                          keyBindings: keyBindings,
                          autoCommitAtFour: autoCommitAtFour,
                          defaultMode: defaultMode,
                          learningEnabled: learningEnabled)
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
