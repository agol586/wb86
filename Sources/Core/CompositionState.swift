enum CompositionKind: Equatable, Sendable {
    case idle
    case composing
}

enum CompositionValidationError: Error, Equatable {
    case pageIndexMismatch
    case candidateCodeMismatch
    case missingSelection
    case unexpectedSelection
    case selectionOutOfBounds
}

struct CompositionSnapshot: Equatable, Sendable {
    let code: InputCode
    let candidates: CandidatePage
    let pageIndex: Int
    let selectionIndex: Int?
}

struct CompositionState: Equatable, Sendable {
    let kind: CompositionKind
    let composition: CompositionSnapshot?

    static let idle = CompositionState(kind: .idle, composition: nil)

    static func composing(code: InputCode, candidates: CandidatePage, pageIndex: Int,
                          selectionIndex: Int?) throws -> CompositionState {
        guard pageIndex == candidates.pageIndex else {
            throw CompositionValidationError.pageIndexMismatch
        }
        guard candidates.items.allSatisfy({ $0.code == code }) else {
            throw CompositionValidationError.candidateCodeMismatch
        }
        if candidates.items.isEmpty {
            guard selectionIndex == nil else { throw CompositionValidationError.unexpectedSelection }
        } else {
            guard let selectionIndex else { throw CompositionValidationError.missingSelection }
            guard candidates.items.indices.contains(selectionIndex) else {
                throw CompositionValidationError.selectionOutOfBounds
            }
        }
        return CompositionState(
            kind: .composing,
            composition: CompositionSnapshot(
                code: code,
                candidates: candidates,
                pageIndex: pageIndex,
                selectionIndex: selectionIndex
            )
        )
    }
}
