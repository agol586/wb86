import Foundation
import XCTest
@testable import MacWubi

final class TextConversionTests: XCTestCase {
    func testPunctuationThenWidthMatrixIsIndependentOfOutputScript() {
        for script in [OutputScript.simplified, .traditional] {
            var converter = PunctuationConverter()
            let chineseHalf = InputMode(language: .chinese, punctuation: .chinese,
                                        width: .half, script: script)
            XCTAssertEqual(converter.convert(",", mode: chineseHalf), "，")
            XCTAssertNil(converter.convert("-", mode: chineseHalf))

            let chineseFull = InputMode(language: .chinese, punctuation: .chinese,
                                        width: .full, script: script)
            XCTAssertEqual(converter.convert(",", mode: chineseFull), "，")
            XCTAssertEqual(converter.convert("-", mode: chineseFull), "－")

            let englishHalf = InputMode(language: .chinese, punctuation: .english,
                                        width: .half, script: script)
            XCTAssertNil(converter.convert(",", mode: englishHalf))

            let englishFull = InputMode(language: .chinese, punctuation: .english,
                                        width: .full, script: script)
            XCTAssertEqual(converter.convert(",", mode: englishFull), "，")
            XCTAssertEqual(converter.convert("\"", mode: englishFull), "＂")

            let directEnglish = InputMode(language: .directEnglish, punctuation: .chinese,
                                          width: .full, script: script)
            XCTAssertEqual(converter.convert(",", mode: directEnglish), "，")
            XCTAssertEqual(converter.convert("A", mode: directEnglish), "Ａ")
        }
    }

    func testChineseAndEnglishPunctuationIncludingPairedQuotes() {
        var converter = PunctuationConverter()
        XCTAssertEqual(converter.convert(",", punctuation: .chinese, width: .half), "，")
        XCTAssertEqual(converter.convert(".", punctuation: .chinese, width: .half), "。")
        XCTAssertEqual(converter.convert("\"", punctuation: .chinese, width: .half), "“")
        XCTAssertEqual(converter.convert("\"", punctuation: .chinese, width: .half), "”")
        XCTAssertEqual(converter.convert("'", punctuation: .chinese, width: .half), "‘")
        XCTAssertEqual(converter.convert("'", punctuation: .chinese, width: .half), "’")
        XCTAssertNil(converter.convert(",", punctuation: .english, width: .half))
    }

    func testFullWidthConversionIsBoundedToPrintableASCII() {
        var converter = PunctuationConverter()
        XCTAssertEqual(converter.convert("A", punctuation: .english, width: .full), "Ａ")
        XCTAssertEqual(converter.convert("1", punctuation: .english, width: .full), "１")
        XCTAssertEqual(converter.convert(" ", punctuation: .english, width: .full), "　")
        XCTAssertNil(converter.convert("中", punctuation: .english, width: .full))
        XCTAssertNil(converter.convert("ab", punctuation: .english, width: .full))
    }

    func testTraditionalKnownVectorsUseLongestPhraseMatch() throws {
        let converter = try ScriptConverter(data: bundledConversionData())
        XCTAssertEqual(converter.convert("中国输入法", to: .traditional), "中國輸入法")
        XCTAssertEqual(converter.convert("开发后台", to: .traditional), "開發後臺")
        XCTAssertEqual(converter.convert("你好" , to: .simplified), "你好")
    }

    func testCandidateConversionPreservesSelectionSemantics() throws {
        let converter = try ScriptConverter(data: bundledConversionData())
        let code = try XCTUnwrap(InputCode("khlg"))
        let candidate = try Candidate(text: "中国", code: code, source: .base,
                                      baseRank: 2, learnedScore: 3, ordinal: 4)

        let converted = try converter.convert(candidate, to: .traditional)

        XCTAssertEqual(converted.text, "中國")
        XCTAssertEqual(converted.code, candidate.code)
        XCTAssertEqual(converted.source, candidate.source)
        XCTAssertEqual(converted.baseRank, candidate.baseRank)
        XCTAssertEqual(converted.learnedScore, candidate.learnedScore)
        XCTAssertEqual(converted.ordinal, candidate.ordinal)
    }

    func testEnginePublishesConvertedCandidatesOnlyInTraditionalMode() throws {
        let converter = try ScriptConverter(data: bundledConversionData())
        let code = try XCTUnwrap(InputCode("k"))
        let candidate = try Candidate(text: "中国", code: code, source: .base,
                                      baseRank: 0, learnedScore: 0, ordinal: 1)
        let engine = InputEngine(
            mode: InputMode(language: .chinese, punctuation: .chinese,
                            width: .half, script: .traditional),
            scriptConverter: converter
        ) { _, pageIndex in
            try CandidatePage(items: [candidate], pageIndex: pageIndex,
                              pageSize: 5, totalCount: 1)
        }

        let result = engine.process(.letter("k"))
        XCTAssertEqual(result.candidateAction.page?.items.first?.text, "中國")
        XCTAssertEqual(result.state.composition?.candidates.items.first?.code, code)
    }

    func testCorruptConversionResourceIsRejectedAtomically() {
        XCTAssertThrowsError(try ScriptConverter(data: Data("invalid".utf8)))
    }

    private func bundledConversionData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "script-conversion", withExtension: "bin")
                ?? Bundle(for: Self.self).url(forResource: "script-conversion", withExtension: "bin")
        )
        return try Data(contentsOf: url)
    }
}
