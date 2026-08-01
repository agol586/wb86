import Foundation

enum CandidatePageKeySet: String, Codable, CaseIterable, Sendable {
    case minusEquals
    case commaPeriod
    case bracketPair
}

enum ModeSwitchBinding: Equatable, Codable, Sendable {
    case controlShiftDigits
    case custom(String)
    case disabled
}

enum KeyBindingError: Error, Equatable {
    case systemReserved
    case emptyCustomBinding
}

struct KeyBindingSettings: Equatable, Codable, Sendable {
    var modeSwitch: ModeSwitchBinding
    var pageKeys: CandidatePageKeySet

    static let `default` = try! KeyBindingSettings(modeSwitch: .controlShiftDigits,
                                                   pageKeys: .minusEquals)

    init(modeSwitch: ModeSwitchBinding, pageKeys: CandidatePageKeySet) throws {
        if case let .custom(raw) = modeSwitch {
            let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { throw KeyBindingError.emptyCustomBinding }
            guard !["control-space", "command-space", "control-option-space"].contains(normalized) else {
                throw KeyBindingError.systemReserved
            }
        }
        self.modeSwitch = modeSwitch
        self.pageKeys = pageKeys
    }
}
