import AppKit

protocol InputClientProxy: AnyObject {
    func setMarkedText(_ text: String) throws
    func commitText(_ text: String) throws
    func clearMarkedText() throws
    func candidateAnchorTopLeft() -> NSPoint?
}

@MainActor
final class InputControllerSession: PrivacySessionControlling, SettingsSessionControlling {
    private let engine: InputEngine
    private let presenter: CandidatePresenting
    private let learningHandler: (LearningDelta, CandidateRankingPolicy) -> Void
    private weak var activeClient: InputClientProxy?
    private(set) var activeSnapshot = SettingsSnapshot(generation: 0, settings: .default)
    private(set) var pendingSnapshot: SettingsSnapshot?
    private(set) var appearanceSettings = InputSettings.default
    private var hasAppliedSettingsSnapshot = false
    private var hasInitializedMode = false

    var settings: InputSettings { activeSnapshot.settings }

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
        self.learningHandler = { delta, _ in learningHandler(delta) }
        presenter.setSelectionHandler { [weak self] ordinal in
            guard let self, let client = self.activeClient else { return }
            _ = self.handle(.select(ordinal), client: client)
        }
    }

    init(engine: InputEngine, presenter: CandidatePresenting,
         policyLearningHandler: @escaping (LearningDelta, CandidateRankingPolicy) -> Void) {
        self.engine = engine
        self.presenter = presenter
        learningHandler = policyLearningHandler
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
            applyPendingSettingsIfIdle()
            return true
        }
        apply(result.candidateAction, client: client)
        if let learningDelta = result.learningDelta {
            learningHandler(learningDelta, activeSnapshot.candidateRankingPolicy)
        }
        applyPendingSettingsIfIdle()
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
        applyPendingSettingsIfIdle()
    }

    func resetWithoutClient() {
        engine.reset()
        presenter.hide()
        activeClient = nil
        applyPendingSettingsIfIdle()
    }

    func reactivate() {
        engine.reset()
        presenter.hide()
        applyPendingSettingsIfIdle()
        engine.initializeMode(from: activeSnapshot.settings.defaultMode)
        hasInitializedMode = true
    }

    func apply(settings: InputSettings) {
        guard state == .idle else { return }
        applyAppearance(settings)
        activeSnapshot = SettingsSnapshot(generation: activeSnapshot.generation,
                                          settings: settings)
        hasAppliedSettingsSnapshot = true
        engine.applyRuntimePolicy(settings: settings, generation: activeSnapshot.generation)
        if !hasInitializedMode {
            engine.initializeMode(from: settings.defaultMode)
            hasInitializedMode = true
        }
    }

    func stage(settingsSnapshot: SettingsSnapshot) {
        let newestGeneration = max(activeSnapshot.generation,
                                   pendingSnapshot?.generation ?? 0)
        guard !hasAppliedSettingsSnapshot || settingsSnapshot.generation >= newestGeneration else {
            return
        }
        applyAppearance(settingsSnapshot.settings)
        if state == .idle {
            applySnapshot(settingsSnapshot)
        } else if pendingSnapshot == nil
                    || settingsSnapshot.generation >= pendingSnapshot!.generation {
            pendingSnapshot = settingsSnapshot
        }
    }

    func applyPendingSettingsIfIdle() {
        guard state == .idle, let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        applySnapshot(pendingSnapshot)
    }

    private func applySnapshot(_ snapshot: SettingsSnapshot) {
        activeSnapshot = snapshot
        hasAppliedSettingsSnapshot = true
        engine.applyRuntimePolicy(settings: snapshot.settings, generation: snapshot.generation)
        if !hasInitializedMode {
            engine.initializeMode(from: snapshot.settings.defaultMode)
            hasInitializedMode = true
        }
    }

    private func applyAppearance(_ settings: InputSettings) {
        appearanceSettings = settings
        (presenter as? CandidateAppearanceApplying)?.apply(settings: settings)
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
