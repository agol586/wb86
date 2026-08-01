import Foundation
import XCTest
@testable import MacWubi

final class ImportPerformanceTests: XCTestCase {
    func testTenThousandRecordsCompleteWithinFiveSecondsAndCommitOnce() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        let store = try UserLexiconStore(writer: writer)
        let data = makeFixture(count: 10_000)
        let start = ContinuousClock.now
        let report = try LexiconImporter(store: store).importText(data)
        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(5))
        XCTAssertEqual(report.acceptedCount, 10_000)
        XCTAssertEqual(store.snapshot.entries.count, 10_000)
        XCTAssertEqual(store.snapshot.generation, 1)
    }

    func testInterruptedImportLeavesExistingSnapshotUnchanged() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        let store = try UserLexiconStore(writer: writer)
        let code = try XCTUnwrap(InputCode("a"))
        try store.upsert(code: code, text: "稳定", fixedRank: nil, createdBy: .manual)
        let before = try Data(contentsOf: writer.currentURL(for: .userLexicon))
        writer.failureInjector = { stage in
            if stage == .afterTemporaryValidation { throw Interruption.expected }
        }
        XCTAssertThrowsError(try LexiconImporter(store: store).importText(makeFixture(count: 100)))
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .userLexicon)), before)
        XCTAssertEqual(store.snapshot.entries.map(\.text), ["稳定"])
    }

    private func makeFixture(count: Int) -> Data {
        var lines = [LexiconTextCodec.header]
        lines.reserveCapacity(count + 1)
        for index in 0..<count {
            var value = index
            var code = ""
            for _ in 0..<4 {
                code.append(Character(UnicodeScalar(97 + value % 25)!))
                value /= 25
            }
            lines.append("\(code)\t迁移词\(index)\t\(index % 10)")
        }
        return Data(lines.joined(separator: "\n").appending("\n").utf8)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiImportPerf-\(UUID().uuidString)")
    }

    private enum Interruption: Error { case expected }
}
