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

    func testDisabledPrivateAndFrozenOffPoliciesIgnoreScoresAndWriteNothing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiLearningPolicy-\(UUID().uuidString)",
                                   isDirectory: true)
        let writer = try SnapshotWriter(rootURL: root)
        let users = try UserLexiconStore(writer: writer)
        let learning = try LearningStore(writer: writer)
        let code = try XCTUnwrap(InputCode("a"))
        try users.upsert(code: code, text: "一", fixedRank: nil, createdBy: .manual)
        try users.upsert(code: code, text: "乙", fixedRank: nil, createdBy: .manual)
        try learning.recordSelection(code: code, candidateText: "乙", amount: 10)
        let coordinator = PersonalizationCoordinator(index: nil, userStore: users,
                                                      learningStore: learning)
        let enabled = CandidateRankingPolicy(settingsGeneration: 1, pageSize: 5,
                                             automaticFrequency: true)
        let frozenOff = CandidateRankingPolicy(settingsGeneration: 2, pageSize: 5,
                                               automaticFrequency: false)

        XCTAssertEqual(try coordinator.page(for: code, pageIndex: 0,
                                            policy: enabled).items.first?.text, "乙")

        for policyCase in [(privateMode: true, learningEnabled: true, policy: enabled),
                           (privateMode: false, learningEnabled: false, policy: enabled),
                           (privateMode: false, learningEnabled: true, policy: frozenOff)] {
            coordinator.setPolicy(privateMode: policyCase.privateMode,
                                  learningEnabled: policyCase.learningEnabled)
            let before = learning.snapshot
            XCTAssertEqual(try coordinator.page(for: code, pageIndex: 0,
                                                policy: policyCase.policy).items.first?.text,
                           "一")
            coordinator.record(LearningDelta(code: code, candidateText: "一", amount: 1),
                               policy: policyCase.policy)
            XCTAssertEqual(learning.snapshot, before)
        }
    }
}

private final class PrivacySessionSpy: PrivacySessionControlling {
    var privateMode = false
    var learningEnabled = true
}
