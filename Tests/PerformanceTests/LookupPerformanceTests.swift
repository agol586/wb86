import Foundation
import XCTest
@testable import MacWubi

final class LookupPerformanceTests: XCTestCase {
    func testEveryAcceptanceLookupCompletesWithinTwoMilliseconds() throws {
        let records = try acceptanceRecords()
        let data = try DictionaryFormatV1.encode(records: records, buildIdentifier: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let query = CandidateQuery(index: DictionaryIndex(image: try DictionaryLoader.load(from: url)),
                                   pageSize: 5)

        for code in Set(records.map(\.code)).sorted() {
            for _ in 0..<20 {
                let start = ContinuousClock.now
                _ = try query.page(for: code, pageIndex: 0)
                let elapsed = start.duration(to: .now)
                XCTAssertLessThan(elapsed, .milliseconds(2), "lookup exceeded 2 ms")
            }
        }
    }

    private func acceptanceRecords() throws -> [DictionaryEntryRecord] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "wb86-acceptance", withExtension: "tsv",
                       subdirectory: "Fixtures/Lexicon")
                ?? bundle.url(forResource: "wb86-acceptance", withExtension: "tsv")
        )
        return try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { line in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                return try DictionaryEntryRecord(
                    code: XCTUnwrap(InputCode(String(fields[0]))),
                    rank: XCTUnwrap(UInt32(fields[2])),
                    text: String(fields[1])
                )
            }
            .sorted { lhs, rhs in
                if lhs.code != rhs.code { return lhs.code < rhs.code }
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
            }
    }
}
