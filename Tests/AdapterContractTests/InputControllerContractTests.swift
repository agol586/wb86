import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class InputControllerContractTests: XCTestCase {
    func testFlagsChangedEdgesPassThroughAndReleasePerformsOneModeSideEffect() throws {
        let baseMask = Int(NSEvent.EventTypeMask.keyDown.rawValue)
        let extended = InputControllerEventRouter.extendingRecognizedEvents(baseMask)
        XCTAssertNotEqual(extended & Int(NSEvent.EventTypeMask.keyDown.rawValue), 0)
        XCTAssertNotEqual(extended & Int(NSEvent.EventTypeMask.flagsChanged.rawValue), 0)

        let router = InputControllerEventRouter()
        let snapshot = SettingsSnapshot(generation: 1, settings: .default)
        let press = router.route(
            try event(type: .flagsChanged, keyCode: 56, characters: "",
                      flags: [.shift], timestamp: 1),
            settingsSnapshot: snapshot,
            isComposing: false
        )
        XCTAssertNil(press.coreEvent)
        XCTAssertTrue(press.mustPassThrough)

        let release = router.route(
            try event(type: .flagsChanged, keyCode: 56, characters: "",
                      timestamp: 1.1),
            settingsSnapshot: snapshot,
            isComposing: false
        )
        XCTAssertEqual(release.coreEvent, .switchLanguage)
        XCTAssertTrue(release.mustPassThrough)

        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter())
        session.stage(settingsSnapshot: snapshot)
        XCTAssertTrue(session.handle(try XCTUnwrap(release.coreEvent),
                                     client: RecordingInputClient()))
        XCTAssertEqual(session.mode.language, .directEnglish)
    }

    func testKeyDownDisqualifiesShiftAndResetDropsOrphanRelease() throws {
        let router = InputControllerEventRouter()
        let snapshot = SettingsSnapshot(generation: 2, settings: .default)
        _ = router.route(try event(type: .flagsChanged, keyCode: 56, characters: "",
                                   flags: [.shift], timestamp: 1),
                         settingsSnapshot: snapshot, isComposing: false)
        let keyDown = router.route(try event(type: .keyDown, keyCode: 0, characters: "x",
                                             flags: [.shift], timestamp: 1.05),
                                   settingsSnapshot: snapshot, isComposing: false)
        XCTAssertEqual(keyDown.coreEvent, .letter("A"))
        XCTAssertFalse(keyDown.mustPassThrough)
        XCTAssertNil(router.route(
            try event(type: .flagsChanged, keyCode: 56, characters: "", timestamp: 1.1),
            settingsSnapshot: snapshot, isComposing: false
        ).coreEvent)

        _ = router.route(try event(type: .flagsChanged, keyCode: 60, characters: "",
                                   flags: [.shift], timestamp: 2),
                         settingsSnapshot: snapshot, isComposing: false)
        router.reset()
        XCTAssertNil(router.route(
            try event(type: .flagsChanged, keyCode: 60, characters: "", timestamp: 2.1),
            settingsSnapshot: snapshot, isComposing: false
        ).coreEvent)
    }

    func testEventMatrixProducesOneCoreEventAndOneFrozenLayoutSnapshotPerKeyDown() throws {
        let provider = ContractKeyboardSnapshotProvider()
        let router = InputControllerEventRouter(
            layoutTranslator: KeyboardLayoutTranslator(systemSnapshotProvider: provider.snapshot)
        )
        var settings = InputSettings.default
        settings.keyBindings.keyboardLayout = .followSystem
        settings.candidate2And3ShortcutsEnabled = true
        let snapshot = SettingsSnapshot(generation: 3, settings: settings)
        let cases: [(NSEvent, Bool, InputEvent)] = [
            (try event(type: .keyDown, keyCode: 0, characters: "x", timestamp: 1),
             false, .letter("a")),
            (try event(type: .keyDown, keyCode: 43, characters: "x", timestamp: 2),
             true, .pagePrevious),
            (try event(type: .keyDown, keyCode: 41, characters: "x", timestamp: 3),
             true, .select(2)),
            (try event(type: .keyDown, keyCode: 18, characters: "x", flags: [.command],
                       timestamp: 4), true, .passThrough)
        ]

        for (event, composing, expected) in cases {
            let route = router.route(event, settingsSnapshot: snapshot, isComposing: composing)
            XCTAssertEqual(route.coreEvent, expected)
            XCTAssertFalse(route.mustPassThrough)
        }
        XCTAssertEqual(provider.snapshotCount, cases.count)
    }

    func testSessionUsesDefaultModeOnlyOnFirstSnapshotAndReactivation() throws {
        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter())
        var settings = InputSettings.default
        settings.defaultMode = InputMode(language: .directEnglish, punctuation: .english,
                                         width: .full, script: .traditional)
        session.stage(settingsSnapshot: SettingsSnapshot(generation: 1, settings: settings))
        XCTAssertEqual(session.mode, settings.defaultMode)

        _ = session.handle(.switchLanguage, client: RecordingInputClient())
        XCTAssertEqual(session.mode.language, .chinese)

        var saved = settings
        saved.defaultMode.width = .half
        saved.defaultMode.script = .simplified
        session.stage(settingsSnapshot: SettingsSnapshot(generation: 2, settings: saved))
        XCTAssertEqual(session.mode.language, .chinese)
        XCTAssertEqual(session.mode.width, .full)

        session.reactivate()
        XCTAssertEqual(session.mode, saved.defaultMode)
    }

    func testOrderedClientActionBatchExecutesOnceAndStopsAfterFailure() throws {
        let code = try XCTUnwrap(InputCode("wqvb"))
        let result = InputProcessingResult(
            state: .idle,
            clientActions: ClientTextActionBatch([
                .commitText("旧候选"),
                .setMarkedText("a"),
                .commitText("不应执行")
            ]),
            candidateAction: .hide,
            consumed: true,
            learningDelta: LearningDelta(code: code, candidateText: "旧候选", amount: 1)
        )

        for failureAttempt in [1, 2] {
            var learned = [LearningDelta]()
            let client = RecordingInputClient()
            client.failureAttempt = failureAttempt
            let presenter = RecordingCandidatePresenter()
            presenter.isVisible = true
            let session = InputControllerSession(engine: InputEngine(query: query),
                                                 presenter: presenter) {
                learned.append($0)
            }

            XCTAssertTrue(session.apply(result, client: client))
            XCTAssertEqual(client.actions,
                           failureAttempt == 1 ? [.cleared]
                               : [.committed("旧候选"), .cleared])
            XCTAssertEqual(client.attemptCount, failureAttempt + 1)
            XCTAssertTrue(learned.isEmpty)
            XCTAssertFalse(presenter.isVisible)
            XCTAssertEqual(session.state, .idle)
        }
    }

    func testFifthCodeBatchCallsClientInCommitThenMarkedTextOrder() throws {
        let client = RecordingInputClient()
        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter())
        var settings = InputSettings.default
        settings.autoCommitAtFour = false
        settings.autoCommitFirstAtFive = true
        session.stage(settingsSnapshot: SettingsSnapshot(generation: 1, settings: settings))

        for letter in ["w", "q", "v", "b"] {
            XCTAssertTrue(session.handle(.letter(letter), client: client))
        }
        XCTAssertTrue(session.handle(.letter("a"), client: client))

        XCTAssertEqual(Array(client.actions.suffix(2)),
                       [.committed("候选1"), .marked("a")])
        XCTAssertEqual(client.actions.filter {
            if case .committed = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(session.state.composition?.code, InputCode("a"))
    }

    func testReentrantPendingSnapshotAppliesOnlyAfterWholeClientBatch() throws {
        let client = RecordingInputClient()
        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter())
        session.stage(settingsSnapshot: SettingsSnapshot(generation: 1, settings: .default))

        var updated = InputSettings.default
        updated.autoCommitFirstAtFive = true
        let pending = SettingsSnapshot(generation: 2, settings: updated)
        var observedGenerations = [UInt64]()
        client.didPerformAction = { action in
            if action == .committed("旧候选") {
                session.stage(settingsSnapshot: pending)
            }
            observedGenerations.append(session.activeSnapshot.generation)
        }
        let result = InputProcessingResult(
            state: .idle,
            clientActions: ClientTextActionBatch([
                .commitText("旧候选"),
                .setMarkedText("a")
            ]),
            candidateAction: .hide,
            consumed: true,
            learningDelta: nil
        )

        XCTAssertTrue(session.apply(result, client: client))
        XCTAssertEqual(client.actions, [.committed("旧候选"), .marked("a")])
        XCTAssertEqual(observedGenerations, [1, 1])
        XCTAssertEqual(session.activeSnapshot.generation, 2)
        XCTAssertNil(session.pendingSnapshot)
    }

    func testMarkedTextCommitAndMouseSelectionUseTheSameEnginePath() throws {
        let client = RecordingInputClient()
        let presenter = RecordingCandidatePresenter()
        let session = InputControllerSession(engine: InputEngine(query: query), presenter: presenter)

        XCTAssertTrue(session.handle(.letter("w"), client: client))
        XCTAssertEqual(client.actions, [.marked("w")])
        XCTAssertTrue(presenter.isVisible)

        presenter.selectionHandler?(2)
        XCTAssertEqual(client.actions, [.marked("w"), .committed("候选2")])
        XCTAssertFalse(presenter.isVisible)
        XCTAssertEqual(session.state, .idle)
    }

    func testCancelAndFocusChangesClearMarkedTextWithoutOriginalString() {
        for cancel in [InputEvent.cancel, .passThrough] {
            let client = RecordingInputClient()
            let presenter = RecordingCandidatePresenter()
            let session = InputControllerSession(engine: InputEngine(query: query), presenter: presenter)
            _ = session.handle(.letter("w"), client: client)

            let consumed = session.handle(cancel, client: client)

            XCTAssertEqual(client.actions, [.marked("w"), .cleared])
            XCTAssertFalse(client.actions.contains(.committed("w")))
            XCTAssertEqual(consumed, cancel != .passThrough)
            XCTAssertEqual(session.state, .idle)
        }

        let client = RecordingInputClient()
        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter())
        _ = session.handle(.letter("w"), client: client)
        session.deactivate(client: client)
        XCTAssertEqual(client.actions.last, .cleared)
        XCTAssertEqual(session.state, .idle)
    }

    func testShortcutPassThroughResetsBeforeReturningUnhandled() {
        let client = RecordingInputClient()
        let presenter = RecordingCandidatePresenter()
        let session = InputControllerSession(engine: InputEngine(query: query), presenter: presenter)
        _ = session.handle(.letter("w"), client: client)

        XCTAssertFalse(session.handle(.passThrough, client: client))
        XCTAssertEqual(client.actions.last, .cleared)
        XCTAssertFalse(presenter.isVisible)
    }

    func testClientFailureResetsAndNeverShowsStaleCandidates() {
        let client = RecordingInputClient()
        client.shouldFail = true
        let presenter = RecordingCandidatePresenter()
        let session = InputControllerSession(engine: InputEngine(query: query), presenter: presenter)

        XCTAssertTrue(session.handle(.letter("w"), client: client))
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(presenter.isVisible)
    }

    func testLearningIsForwardedOnlyAfterSuccessfulClientCommit() {
        var learned = [LearningDelta]()
        let client = RecordingInputClient()
        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter()) {
            learned.append($0)
        }
        _ = session.handle(.letter("w"), client: client)
        _ = session.handle(.select(2), client: client)
        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned.first?.candidateText, "候选2")

        let failingClient = RecordingInputClient()
        failingClient.shouldFail = true
        let failing = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: RecordingCandidatePresenter()) {
            learned.append($0)
        }
        _ = failing.handle(.letter("w"), client: failingClient)
        _ = failing.handle(.select(2), client: failingClient)
        XCTAssertEqual(learned.count, 1)
    }

    private func query(code: InputCode, pageIndex: Int) throws -> CandidatePage {
        let candidates = try [1, 2].map {
            try Candidate(text: "候选\($0)", code: code, source: .base,
                          baseRank: $0 - 1, learnedScore: 0, ordinal: $0)
        }
        return try CandidatePage(items: candidates, pageIndex: pageIndex,
                                 pageSize: 5, totalCount: 2)
    }

    private func event(type: NSEvent.EventType, keyCode: UInt16, characters: String,
                       flags: NSEvent.ModifierFlags = [],
                       timestamp: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

private struct ContractKeyboardSnapshot: KeyboardLayoutSnapshot {
    let identifier = "contract-layout"
    func translate(keyCode: UInt16,
                   modifiers: NSEvent.ModifierFlags) -> KeyboardLayoutTranslation {
        switch keyCode {
        case 0: return .character("a")
        case 43: return .character(",")
        case 41: return .character(";")
        case 18: return .character("1")
        default: return .unavailable
        }
    }
}

private final class ContractKeyboardSnapshotProvider {
    private(set) var snapshotCount = 0
    func snapshot() -> (any KeyboardLayoutSnapshot)? {
        snapshotCount += 1
        return ContractKeyboardSnapshot()
    }
}

private final class RecordingInputClient: InputClientProxy {
    enum Action: Equatable { case marked(String), committed(String), cleared }
    var actions = [Action]()
    var didPerformAction: ((Action) -> Void)?
    var shouldFail = false
    var failureAttempt: Int?
    private(set) var attemptCount = 0

    private func checkFailure() throws {
        attemptCount += 1
        if shouldFail || attemptCount == failureAttempt { throw ClientError.failed }
    }

    func setMarkedText(_ text: String) throws {
        try checkFailure()
        let action = Action.marked(text)
        actions.append(action)
        didPerformAction?(action)
    }

    func commitText(_ text: String) throws {
        try checkFailure()
        let action = Action.committed(text)
        actions.append(action)
        didPerformAction?(action)
    }

    func clearMarkedText() throws {
        try checkFailure()
        let action = Action.cleared
        actions.append(action)
        didPerformAction?(action)
    }

    func candidateAnchorTopLeft() -> NSPoint? { NSPoint(x: 100, y: 100) }
    private enum ClientError: Error { case failed }
}

private final class RecordingCandidatePresenter: CandidatePresenting {
    var isVisible = false
    var selectionHandler: ((Int) -> Void)?
    var page: CandidatePage?

    func update(with page: CandidatePage) { self.page = page }
    func show() { isVisible = true }
    func hide() { isVisible = false }
    func setAnchorTopLeft(_ point: NSPoint) {}
    func setSelectionHandler(_ handler: @escaping (Int) -> Void) { selectionHandler = handler }
}
