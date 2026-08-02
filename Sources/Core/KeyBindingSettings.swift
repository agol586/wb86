import Foundation

enum CandidatePageKeyGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case commaPeriod
    case minusEquals
    case bracketPair
    case tab
    case arrows
}

enum CandidatePageKeySet: String, Codable, CaseIterable, Sendable {
    case minusEquals
    case commaPeriod
    case bracketPair

    var group: CandidatePageKeyGroup {
        switch self {
        case .minusEquals: return .minusEquals
        case .commaPeriod: return .commaPeriod
        case .bracketPair: return .bracketPair
        }
    }
}

enum KeyboardLayoutSelection: String, Codable, CaseIterable, Sendable {
    case followSystem
    case us
}

enum ModeSwitchBinding: Equatable, Codable, Sendable {
    case standaloneShift
    case controlShiftF
    case shiftSpace
    case legacyControlShiftDigits
    case custom(String)
    case disabled

    /// Old source name retained until schema-v1 migration is removed.
    static let controlShiftDigits = ModeSwitchBinding.legacyControlShiftDigits
}

enum KeyBindingError: Error, Equatable {
    case systemReserved
    case emptyCustomBinding
    case unsupportedLegacyBinding
}

struct KeyBindingSettings: Equatable, Codable, Sendable {
    var languageSwitch: ModeSwitchBinding
    var scriptSwitch: ModeSwitchBinding
    var widthSwitch: ModeSwitchBinding
    var pageKeyGroups: Set<CandidatePageKeyGroup>
    var keyboardLayout: KeyboardLayoutSelection

    static let `default` = try! KeyBindingSettings(
        languageSwitch: .standaloneShift,
        scriptSwitch: .controlShiftF,
        widthSwitch: .disabled,
        pageKeyGroups: [.commaPeriod, .minusEquals, .bracketPair, .tab],
        keyboardLayout: .us
    )

    static let migrationCompatibilityDefault = try! KeyBindingSettings(
        languageSwitch: .legacyControlShiftDigits,
        scriptSwitch: .legacyControlShiftDigits,
        widthSwitch: .legacyControlShiftDigits,
        pageKeyGroups: [.minusEquals],
        keyboardLayout: .followSystem
    )

    init(languageSwitch: ModeSwitchBinding, scriptSwitch: ModeSwitchBinding,
         widthSwitch: ModeSwitchBinding, pageKeyGroups: Set<CandidatePageKeyGroup>,
         keyboardLayout: KeyboardLayoutSelection) throws {
        try Self.validateLegacyCustom(languageSwitch)
        try Self.validateLegacyCustom(scriptSwitch)
        try Self.validateLegacyCustom(widthSwitch)
        self.languageSwitch = languageSwitch
        self.scriptSwitch = scriptSwitch
        self.widthSwitch = widthSwitch
        self.pageKeyGroups = pageKeyGroups
        self.keyboardLayout = keyboardLayout
    }

    /// Compatibility initializer used by schema-v1 tests and migration.
    init(modeSwitch: ModeSwitchBinding, pageKeys: CandidatePageKeySet) throws {
        try Self.validateLegacyCustom(modeSwitch)
        self.languageSwitch = modeSwitch
        self.scriptSwitch = modeSwitch
        self.widthSwitch = modeSwitch
        self.pageKeyGroups = [pageKeys.group]
        self.keyboardLayout = .followSystem
    }

    /// Compatibility view for existing input mapping until it adopts independent bindings.
    var modeSwitch: ModeSwitchBinding {
        get { languageSwitch }
        set { languageSwitch = newValue }
    }

    /// Compatibility view for the former single page-key setting.
    var pageKeys: CandidatePageKeySet {
        get {
            if pageKeyGroups.contains(.minusEquals) { return .minusEquals }
            if pageKeyGroups.contains(.commaPeriod) { return .commaPeriod }
            if pageKeyGroups.contains(.bracketPair) { return .bracketPair }
            return .minusEquals
        }
        set { pageKeyGroups = [newValue.group] }
    }

    private static func validateLegacyCustom(_ binding: ModeSwitchBinding) throws {
        guard case let .custom(raw) = binding else { return }
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw KeyBindingError.emptyCustomBinding }
        guard !["control-space", "command-space", "control-option-space"].contains(normalized) else {
            throw KeyBindingError.systemReserved
        }
    }
}
