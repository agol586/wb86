import AppKit

protocol InputClientProxy: AnyObject {
    func setMarkedText(_ text: String) throws
    func commitText(_ text: String) throws
    func clearMarkedText() throws
    func candidateAnchorTopLeft() -> NSPoint?
}

final class InputControllerSession: PrivacySessionControlling, SettingsSessionControlling {
    private let engine: InputEngine
    private let presenter: CandidatePresenting
    private let learningHandler: (LearningDelta) -> Void
    private weak var activeClient: InputClientProxy?
    private(set) var settings = InputSettings.default

    var state: CompositionState { engine.state }
    var mode: InputMode { engine.mode }
    var privateMode: Bool {
        get { engine.privateMode }
        set { engine.privateMode = newValue }
    }
    var learningEnabled: Bool {
        get { engine.learningEnabled }
        set { engine.learningEnabled = newValue }
    }

    init(engine: InputEngine, presenter: CandidatePresenting,
         learningHandler: @escaping (LearningDelta) -> Void = { _ in }) {
        self.engine = engine
        self.presenter = presenter
        self.learningHandler = learningHandler
        presenter.setSelectionHandler { [weak self] ordinal in
            guard let self, let client = self.activeClient else { return }
            _ = self.handle(.select(ordinal), client: client)
        }
    }

    @discardableResult
    func handle(_ event: InputEvent, client: InputClientProxy) -> Bool {
        activeClient = client
        let result = engine.process(event)
        return apply(result, client: client)
    }

    @discardableResult
    func apply(_ result: InputProcessingResult, client: InputClientProxy) -> Bool {
        activeClient = client
        do {
            for action in result.clientActions.actions {
                try apply(action, to: client)
            }
        } catch {
            recover(client: client)
            return true
        }
        apply(result.candidateAction, client: client)
        if let learningDelta = result.learningDelta { learningHandler(learningDelta) }
        return result.consumed
    }

    func deactivate(client: InputClientProxy) {
        activeClient = client
        if engine.state.kind == .composing {
            _ = handle(.cancel, client: client)
        } else {
            presenter.hide()
        }
        activeClient = nil
    }

    func resetWithoutClient() {
        engine.reset()
        presenter.hide()
        activeClient = nil
    }

    func apply(settings: InputSettings) {
        guard state == .idle else { return }
        self.settings = settings
        engine.apply(settings: settings)
        (presenter as? AccessibleCandidatePresenter)?.apply(settings: settings)
    }

    private func apply(_ action: ClientTextAction, to client: InputClientProxy) throws {
        switch action {
        case .none:
            break
        case let .setMarkedText(text):
            try client.setMarkedText(text)
        case let .commitText(text):
            try client.commitText(text)
        case .clearMarkedText:
            try client.clearMarkedText()
        }
    }

    private func apply(_ action: CandidateWindowAction, client: InputClientProxy) {
        switch action {
        case .none:
            break
        case let .show(page):
            presenter.update(with: page)
            if let anchor = client.candidateAnchorTopLeft() {
                presenter.setAnchorTopLeft(anchor)
            }
            presenter.show()
        case .hide:
            presenter.hide()
        }
    }

    private func recover(client: InputClientProxy) {
        engine.reset()
        presenter.hide()
        try? client.clearMarkedText()
    }
}
