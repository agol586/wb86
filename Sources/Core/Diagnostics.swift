import Foundation

enum DiagnosticCategory: String, CaseIterable, Hashable, Sendable {
    case dictionaryLoadFailure
    case invalidEvent
    case clientOperationFailure
    case candidatePresentationFailure
    case persistenceFailure
    case migrationFailure
    case importFailure
    case performanceGateExceeded
}

final class DiagnosticCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = [DiagnosticCategory: UInt64]()

    func record(_ category: DiagnosticCategory) {
        lock.lock()
        defer { lock.unlock() }
        let current = counts[category, default: 0]
        counts[category] = current == UInt64.max ? UInt64.max : current + 1
    }

    func count(for category: DiagnosticCategory) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counts[category, default: 0]
    }

    func snapshot() -> [DiagnosticCategory: UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }
}

enum DiagnosticFormatter {
    static func report(_ counts: [DiagnosticCategory: UInt64]) -> String {
        counts.filter { $0.value > 0 }.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\(snakeCase($0.key.rawValue))=\($0.value)" }.joined(separator: "\n")
    }

    private static func snakeCase(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character.isUppercase {
                if !result.isEmpty { result.append("_") }
                result.append(contentsOf: character.lowercased())
            } else { result.append(character) }
        }
    }
}
