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
    let sequence: CompositionKeySequence
    let route: CompositionRoute
    let candidates: CandidatePage
    let pageIndex: Int
    let selectionIndex: Int?

    var code: InputCode? { sequence.wubiCode }
}

struct CompositionState: Equatable, Sendable {
    let kind: CompositionKind
    let composition: CompositionSnapshot?

    static let idle = CompositionState(kind: .idle, composition: nil)

    static func composing(code: InputCode, candidates: CandidatePage, pageIndex: Int,
                          selectionIndex: Int?) throws -> CompositionState {
        try composing(sequence: CompositionKeySequence(code.letters)!, route: .wubiOnly,
                      candidates: candidates, pageIndex: pageIndex,
                      selectionIndex: selectionIndex)
    }

    static func composing(sequence: CompositionKeySequence, route: CompositionRoute,
                          candidates: CandidatePage, pageIndex: Int,
                          selectionIndex: Int?) throws -> CompositionState {
        guard pageIndex == candidates.pageIndex else {
            throw CompositionValidationError.pageIndexMismatch
        }
        guard candidates.items.allSatisfy({ $0.queryKey.normalizedCode == sequence.letters }) else {
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
                sequence: sequence,
                route: route,
                candidates: candidates,
                pageIndex: pageIndex,
                selectionIndex: selectionIndex
            )
        )
    }
}
