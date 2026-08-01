import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class CrossApplicationCompatibilityTests: XCTestCase {
    private let applicationFixtures = [
        "native-editor", "browser", "office", "code-editor",
        "terminal", "system-search", "electron"
    ]

    func testSevenApplicationFixturesUseIdenticalMarkedAndCommitContract() throws {
        XCTAssertEqual(applicationFixtures.count, 7)
        for fixture in applicationFixtures {
            let client = CompatibilityClient(fixture: fixture)
            let presenter = NullCandidatePresenter()
            let session = InputControllerSession(engine: InputEngine(query: query), presenter: presenter)
            XCTAssertTrue(session.handle(.letter("a"), client: client), fixture)
            XCTAssertTrue(session.handle(.selectFirst, client: client), fixture)
            XCTAssertEqual(client.marked, ["a"], fixture)
            XCTAssertEqual(client.committed, ["兼容"], fixture)
            XCTAssertEqual(session.state, .idle, fixture)
            XCTAssertFalse(presenter.isVisible, fixture)
        }
    }

    func testFocusAndSessionChurnNeverCrossCommits() {
        let firstClient = CompatibilityClient(fixture: "browser")
        let secondClient = CompatibilityClient(fixture: "terminal")
        let first = InputControllerSession(engine: InputEngine(query: query),
                                           presenter: NullCandidatePresenter())
        let second = InputControllerSession(engine: InputEngine(query: query),
                                            presenter: NullCandidatePresenter())
        _ = first.handle(.letter("a"), client: firstClient)
        first.deactivate(client: firstClient)
        _ = second.handle(.letter("b"), client: secondClient)
        _ = second.handle(.selectFirst, client: secondClient)

        XCTAssertTrue(firstClient.committed.isEmpty)
        XCTAssertEqual(firstClient.clearCount, 1)
        XCTAssertEqual(secondClient.committed, ["兼容"])
        XCTAssertEqual(first.state, .idle)
        XCTAssertEqual(second.state, .idle)
    }

    private func query(code: InputCode, pageIndex: Int) throws -> CandidatePage {
        try CandidatePage(items: [Candidate(text: "兼容", code: code, source: .base,
                                            baseRank: 0, learnedScore: 0, ordinal: 1)],
                          pageIndex: pageIndex, pageSize: 5, totalCount: 1)
    }
}

private final class CompatibilityClient: InputClientProxy {
    let fixture: String
    var marked = [String]()
    var committed = [String]()
    var clearCount = 0
    init(fixture: String) { self.fixture = fixture }
    func setMarkedText(_ text: String) throws { marked.append(text) }
    func commitText(_ text: String) throws { committed.append(text) }
    func clearMarkedText() throws { clearCount += 1 }
    func candidateAnchorTopLeft() -> NSPoint? {
        fixture == "system-search" ? nil : NSPoint(x: 100, y: 100)
    }
}
