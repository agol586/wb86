enum ClientTextAction: Equatable, Sendable {
    case none
    case setMarkedText(String)
    case commitText(String)
    case clearMarkedText
}

enum CandidateWindowAction: Equatable, Sendable {
    case none
    case show(CandidatePage)
    case hide

    var page: CandidatePage? {
        guard case let .show(page) = self else { return nil }
        return page
    }
}

struct LearningDelta: Equatable, Sendable {
    let code: InputCode
    let candidateText: String
    let amount: Int
}

struct InputProcessingResult: Equatable, Sendable {
    let state: CompositionState
    let clientAction: ClientTextAction
    let candidateAction: CandidateWindowAction
    let consumed: Bool
    let learningDelta: LearningDelta?
}

final class InputEngine {
    typealias Query = (_ code: InputCode, _ pageIndex: Int) throws -> CandidatePage

    private let query: Query
    private let scriptConverter: ScriptConverter?
    private(set) var state = CompositionState.idle
    private(set) var mode: InputMode
    private var punctuationConverter = PunctuationConverter()
    var secureInput = false
    var privateMode = false
    var learningEnabled = true
    private var autoCommitAtFour = false

    init(mode: InputMode = .default, scriptConverter: ScriptConverter? = nil,
         query: @escaping Query) {
        self.mode = mode
        self.scriptConverter = scriptConverter
        self.query = query
    }

    @discardableResult
    func process(_ event: InputEvent) -> InputProcessingResult {
        if mode.language == .directEnglish, case .letter = event {
            return result(state: state, consumed: false)
        }

        switch event {
        case let .letter(letter):
            return processLetter(letter)
        case let .select(ordinal):
            return processSelection(ordinal)
        case .selectFirst:
            return processSelection(1)
        case .pagePrevious:
            return processPage(delta: -1)
        case .pageNext:
            return processPage(delta: 1)
        case .backspace:
            return processBackspace()
        case .cancel:
            return clearIfComposing(consumedWhenComposing: true)
        case let .text(text):
            return processText(text)
        case .passThrough:
            return clearIfComposing(consumedWhenComposing: false)
        case .switchLanguage:
            return switchMode { mode in
                mode.language = mode.language == .chinese ? .directEnglish : .chinese
            }
        case .switchPunctuation:
            return switchMode { mode in
                mode.punctuation = mode.punctuation == .chinese ? .english : .chinese
            }
        case .switchWidth:
            return switchMode { mode in
                mode.width = mode.width == .half ? .full : .half
            }
        case .switchScript:
            return switchMode { mode in
                mode.script = mode.script == .simplified ? .traditional : .simplified
            }
        }
    }

    func reset() {
        state = .idle
    }

    func apply(settings: InputSettings) {
        guard state == .idle else { return }
        mode = settings.defaultMode
        learningEnabled = settings.learningEnabled
        autoCommitAtFour = settings.autoCommitAtFour
    }

    private func processLetter(_ rawLetter: String) -> InputProcessingResult {
        let existing = state.composition?.sequence.letters ?? ""
        guard existing.utf8.count < 4, let code = InputCode(existing + rawLetter) else {
            return recoverFromError()
        }
        return queryAndCompose(code: code, pageIndex: 0)
    }

    private func processText(_ text: String) -> InputProcessingResult {
        if state.kind == .composing {
            return clearIfComposing(consumedWhenComposing: false)
        }
        guard mode.language == .chinese else {
            return result(state: .idle, consumed: false)
        }
        guard let converted = punctuationConverter.convert(
            text,
            punctuation: mode.punctuation,
            width: mode.width
        ) else {
            return result(state: .idle, consumed: false)
        }
        return result(state: .idle, clientAction: .commitText(converted), consumed: true)
    }

    private func switchMode(_ update: (inout InputMode) -> Void) -> InputProcessingResult {
        let wasComposing = state.kind == .composing
        if wasComposing { state = .idle }
        update(&mode)
        return result(
            state: .idle,
            clientAction: wasComposing ? .clearMarkedText : .none,
            candidateAction: wasComposing ? .hide : .none,
            consumed: true
        )
    }

    private func processSelection(_ ordinal: Int) -> InputProcessingResult {
        guard let composition = state.composition else {
            return result(state: state, consumed: false)
        }
        guard (1...9).contains(ordinal),
              let candidate = composition.candidates.items.first(where: { $0.ordinal == ordinal }) else {
            return result(state: state, consumed: true)
        }

        state = .idle
        let learning = secureInput || privateMode || !learningEnabled ? nil
            : composition.code.map { LearningDelta(
            code: $0,
            candidateText: candidate.text,
            amount: 1
        ) }
        return result(
            state: .idle,
            clientAction: .commitText(candidate.text),
            candidateAction: .hide,
            consumed: true,
            learningDelta: learning
        )
    }

    private func processPage(delta: Int) -> InputProcessingResult {
        guard let composition = state.composition else {
            return result(state: state, consumed: false)
        }
        if (delta < 0 && !composition.candidates.hasPrevious)
            || (delta > 0 && !composition.candidates.hasNext) {
            return result(state: state, consumed: true)
        }
        guard let code = composition.code else { return recoverFromError() }
        return queryAndCompose(code: code, pageIndex: composition.pageIndex + delta)
    }

    private func processBackspace() -> InputProcessingResult {
        guard let composition = state.composition else {
            return result(state: state, consumed: false)
        }
        if composition.sequence.length == 1 {
            state = .idle
            return result(state: .idle, clientAction: .clearMarkedText,
                          candidateAction: .hide, consumed: true)
        }
        let shortened = String(composition.sequence.letters.dropLast())
        guard let code = InputCode(shortened) else { return recoverFromError() }
        return queryAndCompose(code: code, pageIndex: 0)
    }

    private func queryAndCompose(code: InputCode, pageIndex: Int) -> InputProcessingResult {
        do {
            let queriedPage = try query(code, pageIndex)
            let page = try scriptConverter?.convert(queriedPage, to: mode.script) ?? queriedPage
            let next = try CompositionState.composing(
                code: code,
                candidates: page,
                pageIndex: pageIndex,
                selectionIndex: page.items.isEmpty ? nil : 0
            )
            state = next
            if autoCommitAtFour, code.length == 4, !page.items.isEmpty {
                return processSelection(1)
            }
            return result(
                state: next,
                clientAction: .setMarkedText(code.letters),
                candidateAction: page.items.isEmpty ? .hide : .show(page),
                consumed: true
            )
        } catch {
            return recoverFromError()
        }
    }

    private func clearIfComposing(consumedWhenComposing: Bool) -> InputProcessingResult {
        guard state.kind == .composing else {
            return result(state: state, consumed: false)
        }
        state = .idle
        return result(state: .idle, clientAction: .clearMarkedText,
                      candidateAction: .hide, consumed: consumedWhenComposing)
    }

    private func recoverFromError() -> InputProcessingResult {
        state = .idle
        return result(state: .idle, clientAction: .clearMarkedText,
                      candidateAction: .hide, consumed: true)
    }

    private func result(state: CompositionState,
                        clientAction: ClientTextAction = .none,
                        candidateAction: CandidateWindowAction = .none,
                        consumed: Bool,
                        learningDelta: LearningDelta? = nil) -> InputProcessingResult {
        InputProcessingResult(
            state: state,
            clientAction: clientAction,
            candidateAction: candidateAction,
            consumed: consumed,
            learningDelta: learningDelta
        )
    }
}
