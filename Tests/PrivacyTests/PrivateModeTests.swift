import XCTest
@testable import MacWubi

final class PrivateModeTests: XCTestCase {
    func testPrivateModeSuppressesLearningDeltaAndExistingScores() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let base = try Candidate(text: "甲", code: code, source: .base,
                                 baseRank: 0, learnedScore: 0, ordinal: 1)
        let learned = try Candidate(text: "乙", code: code, source: .base,
                                    baseRank: 1, learnedScore: 99, ordinal: 2)
        let ranked = CandidateRanker.rank(candidates: [base, learned], learningEnabled: false)
        XCTAssertEqual(ranked.map(\.text), ["甲", "乙"])

        let engine = InputEngine { _, pageIndex in
            try CandidatePage(items: [base, learned], pageIndex: pageIndex,
                              pageSize: 5, totalCount: 2)
        }
        engine.privateMode = true
        _ = engine.process(.letter("a"))
        XCTAssertNil(engine.process(.select(2)).learningDelta)
    }

    func testControllerAtomicallyUpdatesEveryRegisteredSession() {
        let first = PrivacySessionSpy()
        let second = PrivacySessionSpy()
        let controller = PrivacyModeController(policyHandler: { _, _ in })
        controller.register(first)
        controller.register(second)
        controller.setPrivateMode(true)
        controller.setLearningEnabled(false)
        XCTAssertTrue(first.privateMode && second.privateMode)
        XCTAssertFalse(first.learningEnabled || second.learningEnabled)
        XCTAssertTrue(controller.indicatorLabel.contains("私密"))
        XCTAssertEqual(controller.commandMenu.items.map(\.title), ["私密模式", "本地学习"])
        XCTAssertEqual(controller.commandMenu.items.map(\.state), [.on, .off])
    }
}

private final class PrivacySessionSpy: PrivacySessionControlling {
    var privateMode = false
    var learningEnabled = true
}
