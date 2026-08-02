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
        var published = [(privateMode: Bool, learningEnabled: Bool)]()
        let controller = PrivacyModeController {
            published.append((privateMode: $0, learningEnabled: $1))
        }
        controller.register(first)
        controller.register(second)

        for state in [(false, false), (true, false), (true, true), (false, true)] {
            controller.setPrivateMode(state.0)
            controller.setLearningEnabled(state.1)
            XCTAssertEqual(first.privateMode, state.0)
            XCTAssertEqual(second.privateMode, state.0)
            XCTAssertEqual(first.learningEnabled, state.1)
            XCTAssertEqual(second.learningEnabled, state.1)
            XCTAssertEqual(controller.privateMode, state.0)
            XCTAssertEqual(controller.learningEnabled, state.1)
        }

        XCTAssertEqual(published.last?.privateMode, false)
        XCTAssertEqual(published.last?.learningEnabled, true)
    }

    func testControllerCreatesNoStandaloneStatusItemOrDuplicateMenu() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/InputMethod/PrivacyModeController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("NSStatusBar.system.statusItem"))
        XCTAssertFalse(source.contains("NSStatusItem"))
        XCTAssertFalse(source.contains("五·学"))
        XCTAssertFalse(source.contains("五·私"))
        XCTAssertFalse(source.contains("commandMenu"))
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
