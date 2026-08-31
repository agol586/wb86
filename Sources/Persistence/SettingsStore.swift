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
    case generationExhausted
    case readbackMismatch
}

struct SettingsSnapshot: Equatable, Sendable {
    let generation: UInt64
    let settings: InputSettings

    var candidateRankingPolicy: CandidateRankingPolicy {
        CandidateRankingPolicy(settingsGeneration: generation,
                               pageSize: settings.candidatePageSize,
                               automaticFrequency: settings.automaticFrequency,
                               extendedCharacterSetEnabled: settings.extendedCharacterSetEnabled)
    }
}

enum SettingsStoreAccess: Equatable, Sendable {
    case writable
    case readOnlyFuture(schemaVersion: UInt32)
    case readOnlyRecoveryFailure
}

struct InputSettings: Equatable, Codable, Sendable {
    static let schemaVersion: UInt32 = 3

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
    var extendedCharacterSetEnabled: Bool

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
        candidate2And3ShortcutsEnabled: false,
        extendedCharacterSetEnabled: false
    )

    /// Conservative values used only when schema-v1 data is migrated.
    static let migrationCompatibilityDefault = try! InputSettings(
        candidatePageSize: 5,
        candidateLayout: .vertical,
        candidateFontScale: 1,
        keyBindings: .migrationCompatibilityDefault,
        autoCommitAtFour: false,
        autoCommitFirstAtFive: false,
        defaultMode: .default,
        automaticFrequency: true,
        mixedPinyinEnabled: false,
        codeHintEnabled: false,
        candidate2And3ShortcutsEnabled: false,
        extendedCharacterSetEnabled: false
    )

    static let `default` = newInstallDefault

    init(candidatePageSize: Int = 5, candidateLayout: CandidateLayout = .vertical,
         candidateFontScale: Double = 1, keyBindings: KeyBindingSettings = .default,
         autoCommitAtFour: Bool = true, autoCommitFirstAtFive: Bool = false,
         defaultMode: InputMode = InputMode(language: .chinese, punctuation: .english,
                                            width: .half, script: .simplified),
         automaticFrequency: Bool = false, mixedPinyinEnabled: Bool = true,
         codeHintEnabled: Bool = true,
         candidate2And3ShortcutsEnabled: Bool = false,
         extendedCharacterSetEnabled: Bool = false) throws {
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
        self.extendedCharacterSetEnabled = extendedCharacterSetEnabled
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
                      candidate2And3ShortcutsEnabled: false,
                      extendedCharacterSetEnabled: false)
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
                          candidate2And3ShortcutsEnabled: candidate2And3ShortcutsEnabled,
                          extendedCharacterSetEnabled: extendedCharacterSetEnabled)
    }
}

final class SettingsStore {
    private let writer: SnapshotWriter
    private(set) var snapshot = SettingsSnapshot(generation: 0, settings: .default)
    private(set) var access = SettingsStoreAccess.writable

    var generation: UInt64 { snapshot.generation }
    var settings: InputSettings { snapshot.settings }

    init(writer: SnapshotWriter) throws {
        self.writer = writer
        if case let .unsupported(version)? = try? writer.preflightCurrentSchema(
            .settings,
            supportedSchemaVersions: [InputSettings.schemaVersion]
        ), version > InputSettings.schemaVersion {
            access = .readOnlyFuture(schemaVersion: version)
            return
        }

        do {
            _ = try writer.recover(
                .settings,
                supportedSchemaVersions: [1, 2, InputSettings.schemaVersion],
                validatePayload: Self.isValidSupportedPayload
            )
            if let version = try writer.load(.settings)?.schemaVersion,
               version < InputSettings.schemaVersion {
                _ = try DataMigrator(writer: writer).migrate(.settings)
            }
        } catch {
            access = .readOnlyRecoveryFailure
            return
        }

        if let recovered = try writer.recover(
            .settings,
            supportedSchemaVersions: [InputSettings.schemaVersion],
            validatePayload: Self.isValidV3Payload
        ) {
            guard let decoded = try? JSONDecoder().decode(InputSettings.self,
                                                          from: recovered.payload) else {
                throw SettingsValidationError.corruptPayload
            }
            snapshot = SettingsSnapshot(generation: recovered.generation,
                                        settings: try decoded.validated())
        } else if FileManager.default.fileExists(atPath: writer.currentURL(for: .settings).path)
                    || FileManager.default.fileExists(
                        atPath: writer.previousURL(for: .settings).path
                    ) {
            access = .readOnlyRecoveryFailure
        }
    }

    func save(_ value: InputSettings) throws {
        guard access == .writable else { throw SettingsValidationError.unsupportedSchema }
        let validated = try value.validated()
        let increment = generation.addingReportingOverflow(1)
        guard !increment.overflow else { throw SettingsValidationError.generationExhausted }
        let nextGeneration = increment.partialValue
        let payload = try JSONEncoder.sorted.encode(validated)
        let encodedSnapshot = try DataSnapshot(domain: .settings,
                                               schemaVersion: InputSettings.schemaVersion,
                                               generation: nextGeneration,
                                               payload: payload)
        try writer.commit(encodedSnapshot) {
            (try? JSONDecoder().decode(InputSettings.self, from: $0).validated()) != nil
        }
        guard try writer.load(.settings) == encodedSnapshot else {
            throw SettingsValidationError.readbackMismatch
        }
        snapshot = SettingsSnapshot(generation: nextGeneration, settings: validated)
    }

    func restoreDefaults() throws { try save(.default) }

    static func migrateV1Payload(_ data: Data) throws -> Data {
        try InputSettingsV1.validateExactShape(data)
        let legacy: InputSettingsV1
        do {
            legacy = try JSONDecoder().decode(InputSettingsV1.self, from: data)
        } catch {
            throw SettingsValidationError.corruptPayload
        }
        let settings = try legacy.v2Settings()
        _ = try settings.v3Settings().validated()
        return try JSONEncoder.sorted.encode(settings)
    }

    static func migrateV2Payload(_ data: Data) throws -> Data {
        try InputSettingsV2.validateExactShape(data)
        let legacy: InputSettingsV2
        do {
            legacy = try JSONDecoder().decode(InputSettingsV2.self, from: data)
        } catch {
            throw SettingsValidationError.corruptPayload
        }
        return try JSONEncoder.sorted.encode(try legacy.v3Settings().validated())
    }

    private static func isValidV3Payload(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(InputSettings.self, from: data).validated()) != nil
    }

    private static func isValidSupportedPayload(_ data: Data) -> Bool {
        isValidV3Payload(data) || (try? migrateV2Payload(data)) != nil
            || (try? migrateV1Payload(data)) != nil
    }
}

private struct InputSettingsV2: Codable {
    let candidatePageSize: Int
    let candidateLayout: CandidateLayout
    let candidateFontScale: Double
    let keyBindings: KeyBindingSettings
    let autoCommitAtFour: Bool
    let autoCommitFirstAtFive: Bool
    let defaultMode: InputMode
    let automaticFrequency: Bool
    let mixedPinyinEnabled: Bool
    let codeHintEnabled: Bool
    let candidate2And3ShortcutsEnabled: Bool

    func v3Settings() throws -> InputSettings {
        try InputSettings(
            candidatePageSize: candidatePageSize,
            candidateLayout: candidateLayout,
            candidateFontScale: candidateFontScale,
            keyBindings: keyBindings,
            autoCommitAtFour: autoCommitAtFour,
            autoCommitFirstAtFive: autoCommitFirstAtFive,
            defaultMode: defaultMode,
            automaticFrequency: automaticFrequency,
            mixedPinyinEnabled: mixedPinyinEnabled,
            codeHintEnabled: codeHintEnabled,
            candidate2And3ShortcutsEnabled: candidate2And3ShortcutsEnabled,
            extendedCharacterSetEnabled: false
        )
    }

    static func validateExactShape(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == topLevelKeys else {
            throw SettingsValidationError.corruptPayload
        }
    }

    private static let topLevelKeys: Set<String> = [
        "candidatePageSize", "candidateLayout", "candidateFontScale", "keyBindings",
        "autoCommitAtFour", "autoCommitFirstAtFive", "defaultMode", "automaticFrequency",
        "mixedPinyinEnabled", "codeHintEnabled", "candidate2And3ShortcutsEnabled"
    ]
}

private struct InputSettingsV1: Decodable {
    let candidatePageSize: Int
    let candidateLayout: CandidateLayout
    let candidateFontScale: Double
    let keyBindings: KeyBindingSettingsV1
    let autoCommitAtFour: Bool
    let defaultMode: InputMode
    let learningEnabled: Bool

    func v2Settings() throws -> InputSettingsV2 {
        InputSettingsV2(
            candidatePageSize: candidatePageSize,
            candidateLayout: candidateLayout,
            candidateFontScale: candidateFontScale,
            keyBindings: try keyBindings.v2Settings(),
            autoCommitAtFour: autoCommitAtFour,
            autoCommitFirstAtFive: false,
            defaultMode: defaultMode,
            automaticFrequency: learningEnabled,
            mixedPinyinEnabled: false,
            codeHintEnabled: false,
            candidate2And3ShortcutsEnabled: false
        )
    }

    static func validateExactShape(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              Set(object.keys) == topLevelKeys,
              let mode = object["defaultMode"] as? [String: Any],
              Set(mode.keys) == modeKeys,
              let bindings = object["keyBindings"] as? [String: Any],
              Set(bindings.keys) == bindingKeys,
              let switchObject = bindings["modeSwitch"] as? [String: Any],
              switchObject.count == 1,
              let switchName = switchObject.keys.first,
              switchCases.contains(switchName),
              let associatedValues = switchObject[switchName] as? [String: Any]
        else {
            throw SettingsValidationError.corruptPayload
        }

        if switchName == "custom" {
            guard Set(associatedValues.keys) == ["_0"],
                  associatedValues["_0"] is String else {
                throw SettingsValidationError.corruptPayload
            }
        } else if !associatedValues.isEmpty {
            throw SettingsValidationError.corruptPayload
        }
    }

    private static let topLevelKeys: Set<String> = [
        "candidatePageSize", "candidateLayout", "candidateFontScale", "keyBindings",
        "autoCommitAtFour", "defaultMode", "learningEnabled"
    ]
    private static let modeKeys: Set<String> = [
        "language", "punctuation", "width", "script"
    ]
    private static let bindingKeys: Set<String> = ["modeSwitch", "pageKeys"]
    private static let switchCases: Set<String> = ["controlShiftDigits", "custom", "disabled"]
}

private struct KeyBindingSettingsV1: Decodable {
    let modeSwitch: ModeSwitchBindingV1
    let pageKeys: CandidatePageKeySet

    func v2Settings() throws -> KeyBindingSettings {
        try KeyBindingSettings(modeSwitch: modeSwitch.v2Binding, pageKeys: pageKeys)
    }
}

private enum ModeSwitchBindingV1: Decodable {
    case controlShiftDigits
    case custom(String)
    case disabled

    var v2Binding: ModeSwitchBinding {
        switch self {
        case .controlShiftDigits: return .legacyControlShiftDigits
        case let .custom(value): return .custom(value)
        case .disabled: return .disabled
        }
    }
}
