import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class InputControllerContractTests: XCTestCase {
    func testOrderedClientActionBatchExecutesOnceAndStopsAfterFailure() throws {
        var learned = [LearningDelta]()
        let client = RecordingInputClient()
        client.failureAttempt = 2
        let presenter = RecordingCandidatePresenter()
        presenter.isVisible = true
        let session = InputControllerSession(engine: InputEngine(query: query),
                                             presenter: presenter) {
            learned.append($0)
        }
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

        XCTAssertTrue(session.apply(result, client: client))
        XCTAssertEqual(client.actions, [.committed("旧候选"), .cleared])
        XCTAssertEqual(client.attemptCount, 3)
        XCTAssertTrue(learned.isEmpty)
        XCTAssertFalse(presenter.isVisible)
        XCTAssertEqual(session.state, .idle)
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
}

private final class RecordingInputClient: InputClientProxy {
    enum Action: Equatable { case marked(String), committed(String), cleared }
    var actions = [Action]()
    var shouldFail = false
    var failureAttempt: Int?
    private(set) var attemptCount = 0

    private func checkFailure() throws {
        attemptCount += 1
        if shouldFail || attemptCount == failureAttempt { throw ClientError.failed }
    }

    func setMarkedText(_ text: String) throws {
        try checkFailure()
        actions.append(.marked(text))
    }

    func commitText(_ text: String) throws {
        try checkFailure()
        actions.append(.committed(text))
    }

    func clearMarkedText() throws {
        try checkFailure()
        actions.append(.cleared)
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
