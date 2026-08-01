import XCTest
@testable import MacWubi

final class ModeInputIntegrationTests: XCTestCase {
    func testDocumentedMixedLanguageModeFlowProducesExpectedTranscript() throws {
        let converter = try ScriptConverter(data: bundledConversionData())
        let words = ["w": "你", "q": "好", "t": "测", "s": "试", "y": "中国"]
        let engine = InputEngine(scriptConverter: converter) { code, pageIndex in
            guard pageIndex == 0, let text = words[code.letters] else {
                return try CandidatePage(items: [], pageIndex: pageIndex,
                                         pageSize: 5, totalCount: 0)
            }
            let candidate = try Candidate(text: text, code: code, source: .base,
                                          baseRank: 0, learnedScore: 0, ordinal: 1)
            return try CandidatePage(items: [candidate], pageIndex: 0,
                                     pageSize: 5, totalCount: 1)
        }
        var transcript = ""

        func send(_ event: InputEvent, raw: String? = nil) {
            let result = engine.process(event)
            if case let .commitText(text) = result.clientAction { transcript.append(text) }
            if !result.consumed, let raw { transcript.append(raw) }
        }

        send(.letter("w")); send(.selectFirst)
        send(.letter("q")); send(.selectFirst)
        send(.text(","), raw: ",")
        send(.switchLanguage)
        for character in "macwubi42" {
            let raw = String(character)
            send(InputCode(raw) == nil ? .text(raw) : .letter(raw), raw: raw)
        }
        send(.switchLanguage)
        send(.text("\""), raw: "\"")
        send(.letter("t")); send(.selectFirst)
        send(.letter("s")); send(.selectFirst)
        send(.text("\""), raw: "\"")
        send(.text("?"), raw: "?")
        send(.switchWidth)
        send(.text("1"), raw: "1"); send(.text("2"), raw: "2")
        send(.switchWidth)
        send(.switchScript)
        send(.letter("y")); send(.selectFirst)

        XCTAssertEqual(transcript, "你好，macwubi42“测试”？１２中國")
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.mode, InputMode(language: .chinese, punctuation: .chinese,
                                               width: .half, script: .traditional))
    }

    private func bundledConversionData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "script-conversion", withExtension: "bin")
                ?? Bundle(for: Self.self).url(forResource: "script-conversion", withExtension: "bin")
        )
        return try Data(contentsOf: url)
    }
}
