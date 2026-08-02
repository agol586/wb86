enum ClientTextAction: Equatable, Sendable {
    case none
    case setMarkedText(String)
    case commitText(String)
    case clearMarkedText
}

struct ClientTextActionBatch: Equatable, Sendable {
    let actions: [ClientTextAction]

    init(_ actions: [ClientTextAction]) {
        self.actions = actions.filter { $0 != .none }
    }

    static let none = ClientTextActionBatch([])

    static func single(_ action: ClientTextAction) -> ClientTextActionBatch {
        ClientTextActionBatch([action])
    }
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
    let clientActions: ClientTextActionBatch
    let candidateAction: CandidateWindowAction
    let consumed: Bool
    let learningDelta: LearningDelta?

    init(state: CompositionState, clientActions: ClientTextActionBatch,
         candidateAction: CandidateWindowAction, consumed: Bool,
         learningDelta: LearningDelta?) {
        self.state = state
        self.clientActions = clientActions
        self.candidateAction = candidateAction
        self.consumed = consumed
        self.learningDelta = learningDelta
    }

    /// Compatibility view for existing single-action consumers. Compound batches
    /// must use `clientActions` so no operation can be silently discarded.
    var clientAction: ClientTextAction {
        clientActions.actions.count == 1 ? clientActions.actions[0] : .none
    }
}

final class InputEngine {
    typealias Query = (_ code: InputCode, _ pageIndex: Int) throws -> CandidatePage
    typealias PolicyQuery = (_ code: InputCode, _ pageIndex: Int,
                             _ policy: CandidateRankingPolicy) throws -> CandidatePage

    private let policyQuery: PolicyQuery
    private let scriptConverter: ScriptConverter?
    private(set) var state = CompositionState.idle
    private(set) var mode: InputMode
    private var punctuationConverter = PunctuationConverter()
    var secureInput = false
    var privateMode = false
    var learningEnabled = true
    private var autoCommitAtFour = false
    private var autoCommitFirstAtFive = false
    private(set) var rankingPolicy = CandidateRankingPolicy(
        settingsGeneration: 0, pageSize: 5, automaticFrequency: true
    )

    init(mode: InputMode = .default, scriptConverter: ScriptConverter? = nil,
         query: @escaping Query) {
        self.mode = mode
        self.scriptConverter = scriptConverter
        policyQuery = { code, pageIndex, _ in try query(code, pageIndex) }
    }

    init(mode: InputMode = .default, scriptConverter: ScriptConverter? = nil,
         policyQuery: @escaping PolicyQuery) {
        self.mode = mode
        self.scriptConverter = scriptConverter
        self.policyQuery = policyQuery
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
        applyRuntimePolicy(settings: settings, generation: rankingPolicy.settingsGeneration)
    }

    func apply(settings: InputSettings, generation: UInt64) {
        applyRuntimePolicy(settings: settings, generation: generation)
    }

    func applyRuntimePolicy(settings: InputSettings, generation: UInt64) {
        guard state == .idle else { return }
        learningEnabled = settings.learningEnabled
        autoCommitAtFour = settings.autoCommitAtFour
        autoCommitFirstAtFive = settings.autoCommitFirstAtFive
        rankingPolicy = CandidateRankingPolicy(
            settingsGeneration: generation,
            pageSize: settings.candidatePageSize,
            automaticFrequency: settings.automaticFrequency
        )
    }

    func initializeMode(from defaultMode: InputMode) {
        guard state == .idle else { return }
        mode = defaultMode
    }

    private func processLetter(_ rawLetter: String) -> InputProcessingResult {
        let existing = state.composition?.sequence.letters ?? ""
        if existing.utf8.count == 4, autoCommitFirstAtFive {
            return processFifthLetter(rawLetter)
        }
        guard existing.utf8.count < 4, let code = InputCode(existing + rawLetter) else {
            return recoverFromError()
        }
        return queryAndCompose(code: code, pageIndex: 0)
    }

    private func processFifthLetter(_ rawLetter: String) -> InputProcessingResult {
        guard let previous = state.composition,
              previous.route == .wubiOnly,
              let previousCode = previous.code,
              let nextCode = InputCode(rawLetter) else {
            return recoverFromError()
        }

        do {
            let queriedNextPage = try policyQuery(nextCode, 0, rankingPolicy)
            let nextPage = try scriptConverter?.convert(queriedNextPage, to: mode.script)
                ?? queriedNextPage
            let nextState = try CompositionState.composing(
                code: nextCode,
                candidates: nextPage,
                pageIndex: 0,
                selectionIndex: nextPage.items.isEmpty ? nil : 0
            )

            var actions = [ClientTextAction]()
            var learning: LearningDelta?
            if previous.pageIndex == 0, let shownFirst = previous.candidates.items.first {
                let queriedCurrentPage = try policyQuery(previousCode, 0, rankingPolicy)
                let currentPage = try scriptConverter?.convert(queriedCurrentPage, to: mode.script)
                    ?? queriedCurrentPage
                if currentPage.pageIndex == 0,
                   let currentFirst = currentPage.items.first,
                   currentFirst.queryKey == shownFirst.queryKey,
                   currentFirst.text == shownFirst.text {
                    actions.append(.commitText(shownFirst.text))
                    if !secureInput, !privateMode, learningEnabled {
                        learning = LearningDelta(code: previousCode,
                                                 candidateText: shownFirst.text,
                                                 amount: 1)
                    }
                }
            }
            actions.append(.setMarkedText(nextCode.letters))
            state = nextState
            return result(
                state: nextState,
                clientActions: ClientTextActionBatch(actions),
                candidateAction: nextPage.items.isEmpty ? .hide : .show(nextPage),
                consumed: true,
                learningDelta: learning
            )
        } catch {
            return recoverFromError()
        }
    }

    private func processText(_ text: String) -> InputProcessingResult {
        if state.kind == .composing {
            return clearIfComposing(consumedWhenComposing: false)
        }
        guard let converted = punctuationConverter.convert(text, mode: mode) else {
            return result(state: .idle, consumed: false)
        }
        return result(state: .idle, clientAction: .commitText(converted), consumed: true)
    }

    private func switchMode(_ update: (inout InputMode) -> Void) -> InputProcessingResult {
        let resetActions = cancelCompositionForModeSwitch()
        update(&mode)
        return result(
            state: .idle,
            clientAction: resetActions.client,
            candidateAction: resetActions.candidates,
            consumed: true
        )
    }

    private func cancelCompositionForModeSwitch()
        -> (client: ClientTextAction, candidates: CandidateWindowAction) {
        guard state.kind == .composing else { return (.none, .none) }
        state = .idle
        return (.clearMarkedText, .hide)
    }

    private func processSelection(_ ordinal: Int) -> InputProcessingResult {
        guard let composition = state.composition else {
            return result(state: state, consumed: false)
        }
        guard (1...9).contains(ordinal),
              let candidate = composition.candidates.items.first(where: { $0.ordinal == ordinal }) else {
            return result(state: state, consumed: false)
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
            return result(state: state, consumed: false)
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
            let queriedPage = try policyQuery(code, pageIndex, rankingPolicy)
            let page = try scriptConverter?.convert(queriedPage, to: mode.script) ?? queriedPage
            let next = try CompositionState.composing(
                code: code,
                candidates: page,
                pageIndex: pageIndex,
                selectionIndex: page.items.isEmpty ? nil : 0
            )
            state = next
            if autoCommitAtFour, code.length == 4, pageIndex == 0,
               page.totalCount == 1, page.items.count == 1 {
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
                        clientActions: ClientTextActionBatch? = nil,
                        candidateAction: CandidateWindowAction = .none,
                        consumed: Bool,
                        learningDelta: LearningDelta? = nil) -> InputProcessingResult {
        InputProcessingResult(
            state: state,
            clientActions: clientActions ?? .single(clientAction),
            candidateAction: candidateAction,
            consumed: consumed,
            learningDelta: learningDelta
        )
    }
}
