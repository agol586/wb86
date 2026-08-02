import Foundation
import XCTest
@testable import MacWubi

final class PinyinDictionaryCompilerTests: XCTestCase {
    func testNFCContinuousKeysDedupeWeightsAndDeterministicOrdering() throws {
        let source = """
        ---
        name: fixture
        ...
        e\u{301}\tNi Hao\t3
        é\tni hao\t8
        阿\tni hao\t8
        字\tzi\t4

        """
        let wubi = try DictionaryFormatV1.encode(records: [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工")
        ], buildIdentifier: 19)

        let first = try compile(source, wb86Image: wubi)
        let second = try compile(source, wb86Image: wubi)

        XCTAssertEqual(first.image, second.image)
        XCTAssertEqual(first.manifest, second.manifest)
        XCTAssertEqual(first.entries.map(\.key), ["nihao", "zi"])
        XCTAssertEqual(first.entries[0].candidates.compactMap(\.text), ["é", "阿"])
        XCTAssertEqual(first.entries[0].candidates.map(\.weight), [8, 8])
        XCTAssertEqual(first.entries[1].candidates.first?.text, "字")
    }

    func testIllegalLinesKeysAndWeightsAreRejectedWithLineOnlyError() throws {
        let invalidLines = [
            "正文\tni-hao\t1",
            "正文\t123\t1",
            "正文\t\t1",
            "正文\tabcdefghijklmnopqrstuvwxyzabcdefg\t1",
            "正文\tni\t-1",
            "正文\tni\tnot-a-weight",
            "正文\tni"
        ]
        let wubi = try emptyWB86()

        for invalid in invalidLines {
            let source = "---\nname: fixture\n...\n\(invalid)\n"
            XCTAssertThrowsError(try compile(source, wb86Image: wubi), invalid) {
                guard case let PinyinDictionaryCompilerError.invalidRecord(line) = $0 else {
                    return XCTFail("unexpected error \($0)")
                }
                XCTAssertEqual(line, 4)
            }
        }
    }

    func testEachKeyKeepsOnlyTopSixtyFourCandidates() throws {
        let rows = (0..<70).map { "词\($0)\tce shi\t\($0)" }.joined(separator: "\n")
        let result = try compile("---\n...\n\(rows)\n", wb86Image: try emptyWB86())

        let candidates = try XCTUnwrap(result.entries.first?.candidates)
        XCTAssertEqual(candidates.count, 64)
        XCTAssertEqual(candidates.map(\.weight), Array((6..<70).reversed()).map(UInt64.init))
    }

    func testWubiHintSelectionUsesFullFourCodeThenRankAndPackedCode() throws {
        let records = try [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "你好"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("abc")), rank: 0, text: "你好"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("abcd")), rank: 0, text: "你好"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("wqvb")), rank: 1, text: "你好")
        ]
        let wubi = try DictionaryFormatV1.encode(records: records, buildIdentifier: 23)
        let result = try compile("---\n...\n你好\tni hao\t9\n", wb86Image: wubi)
        let candidate = try XCTUnwrap(result.entries.first?.candidates.first)

        XCTAssertEqual(candidate.wubiRecordIndex, 2)
        XCTAssertEqual(candidate.wubiHint?.letters, "abcd")
        let decoded = try PinyinDictionaryFormatV1.decode(
            result.image, expectedWB86BuildIdentifier: 23
        )
        XCTAssertEqual(decoded.entries.first?.candidates.first?.wubiRecordIndex, 2)
        XCTAssertNil(decoded.entries.first?.candidates.first?.text)
    }

    func testSimplificationRunsBeforeFinalTextDedupe() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "script-conversion", withExtension: "bin")
                ?? Bundle(for: Self.self).url(forResource: "script-conversion",
                                              withExtension: "bin")
        )
        let simplifier = try PinyinTextSimplifier(data: Data(contentsOf: url))
        let result = try compile("---\n...\n罢\tba\t5\n罷\tba\t9\n",
                                 wb86Image: try emptyWB86(), simplifier: simplifier)

        XCTAssertEqual(result.entries.first?.candidates.count, 1)
        XCTAssertEqual(result.entries.first?.candidates.first?.text, "罢")
        XCTAssertEqual(result.entries.first?.candidates.first?.weight, 9)
    }

    private func compile(_ source: String, wb86Image: Data,
                         simplifier: PinyinTextSimplifier? = nil) throws
        -> PinyinDictionaryCompilation {
        try PinyinDictionaryCompiler.compile(
            source: source,
            wb86Image: wb86Image,
            sourceRevision: "fixture-revision",
            upstreamSHA256: String(repeating: "a", count: 64),
            licenseIdentifier: "Apache-2.0",
            simplifier: simplifier
        )
    }

    private func emptyWB86() throws -> Data {
        try DictionaryFormatV1.encode(records: [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工")
        ], buildIdentifier: 11)
    }
}
