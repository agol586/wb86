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

enum KeyBindingField: String, Equatable, Sendable {
    case languageSwitch
    case scriptSwitch
    case widthSwitch
    case keyboardLayout
}

enum KeyBindingConflictReason: Equatable, Sendable {
    case empty
    case duplicate(existing: KeyBindingField)
    case rangeOverlap(existing: KeyBindingField)
    case systemReserved
    case unsupportedLegacy
    case layoutUnavailable
}

struct KeyBindingConflict: Equatable, Sendable {
    let field: KeyBindingField
    let reason: KeyBindingConflictReason
}

struct KeyBindingValidationResult: Equatable, Sendable {
    let conflicts: [KeyBindingConflict]
    var isValid: Bool { conflicts.isEmpty }
}

struct KeyBindingValidator {
    typealias LayoutAvailability = (KeyboardLayoutSelection) -> Bool

    private let isLayoutAvailable: LayoutAvailability

    init(isLayoutAvailable: @escaping LayoutAvailability = { _ in true }) {
        self.isLayoutAvailable = isLayoutAvailable
    }

    func validate(_ settings: KeyBindingSettings) -> KeyBindingValidationResult {
        validate(languageSwitch: settings.languageSwitch,
                 scriptSwitch: settings.scriptSwitch,
                 widthSwitch: settings.widthSwitch,
                 keyboardLayout: settings.keyboardLayout)
    }

    func validate(languageSwitch: ModeSwitchBinding,
                  scriptSwitch: ModeSwitchBinding,
                  widthSwitch: ModeSwitchBinding,
                  keyboardLayout: KeyboardLayoutSelection) -> KeyBindingValidationResult {
        let fields: [(KeyBindingField, ModeSwitchBinding)] = [
            (.languageSwitch, languageSwitch),
            (.scriptSwitch, scriptSwitch),
            (.widthSwitch, widthSwitch)
        ]
        var conflicts = [KeyBindingConflict]()
        var acceptedTriggers = [(KeyBindingField, BindingTrigger)]()

        for (field, binding) in fields {
            if let reason = fieldConflict(for: binding) {
                conflicts.append(KeyBindingConflict(field: field, reason: reason))
            }
            guard let trigger = BindingTrigger(binding) else { continue }
            for (existingField, existingTrigger) in acceptedTriggers {
                if trigger == existingTrigger {
                    conflicts.append(KeyBindingConflict(
                        field: field,
                        reason: .duplicate(existing: existingField)
                    ))
                    break
                }
                if trigger.overlaps(existingTrigger) {
                    conflicts.append(KeyBindingConflict(
                        field: field,
                        reason: .rangeOverlap(existing: existingField)
                    ))
                    break
                }
            }
            acceptedTriggers.append((field, trigger))
        }

        if keyboardLayout == .followSystem, !isLayoutAvailable(keyboardLayout) {
            conflicts.append(KeyBindingConflict(field: .keyboardLayout,
                                                reason: .layoutUnavailable))
        }
        return KeyBindingValidationResult(conflicts: conflicts)
    }

    private func fieldConflict(for binding: ModeSwitchBinding) -> KeyBindingConflictReason? {
        switch binding {
        case .legacyControlShiftDigits:
            return .unsupportedLegacy
        case let .custom(raw):
            let normalized = Self.normalize(raw)
            if normalized.isEmpty { return .empty }
            if Self.systemReserved.contains(normalized) { return .systemReserved }
            return nil
        case .standaloneShift, .controlShiftF, .shiftSpace, .disabled:
            return nil
        }
    }

    private static let systemReserved: Set<String> = [
        "control-space", "command-space", "control-option-space"
    ]

    private static func normalize(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "+", with: "-")
    }

    private enum BindingTrigger: Equatable {
        case exact(String)
        case numberedRange(prefix: String, values: ClosedRange<Int>)

        init?(_ binding: ModeSwitchBinding) {
            switch binding {
            case .standaloneShift:
                self = .exact("standalone-shift")
            case .controlShiftF:
                self = .exact("control-shift-f")
            case .shiftSpace:
                self = .exact("shift-space")
            case .legacyControlShiftDigits:
                self = .numberedRange(prefix: "control-shift", values: 1...4)
            case let .custom(raw):
                let normalized = KeyBindingValidator.normalize(raw)
                guard !normalized.isEmpty,
                      !KeyBindingValidator.systemReserved.contains(normalized) else { return nil }
                self = .exact(normalized)
            case .disabled:
                return nil
            }
        }

        func overlaps(_ other: BindingTrigger) -> Bool {
            switch (self, other) {
            case let (.exact(value), .numberedRange(prefix, values)),
                 let (.numberedRange(prefix, values), .exact(value)):
                guard let numbered = Self.numberedExact(value),
                      numbered.prefix == prefix else { return false }
                return values.contains(numbered.value)
            case let (.numberedRange(firstPrefix, firstValues),
                      .numberedRange(secondPrefix, secondValues)):
                guard firstPrefix == secondPrefix else { return false }
                return firstValues.overlaps(secondValues)
            case (.exact, .exact):
                return false
            }
        }

        private static func numberedExact(_ value: String) -> (prefix: String, value: Int)? {
            guard let separator = value.lastIndex(of: "-") else { return nil }
            let numberStart = value.index(after: separator)
            guard let number = Int(value[numberStart...]) else { return nil }
            return (String(value[..<separator]), number)
        }
    }
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
