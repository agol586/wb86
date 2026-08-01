import Foundation
import XCTest
@testable import MacWubi

final class DailyInputIntegrationTests: XCTestCase {
    func testDeterministicTenMinuteDailyInputTranscript() throws {
        let scenario = makeTenMinuteScenario()
        XCTAssertEqual(scenario.durationSeconds, 600)
        XCTAssertEqual(scenario.events.first?.second, 0)
        XCTAssertLessThan(scenario.events.last?.second ?? 600, scenario.durationSeconds)

        let resourceURL = try XCTUnwrap(
            Bundle.main.url(forResource: "wb86", withExtension: "bin")
                ?? Bundle(for: Self.self).url(forResource: "wb86", withExtension: "bin")
        )
        let image = try DictionaryLoader.load(from: resourceURL)
        let query = CandidateQuery(index: DictionaryIndex(image: image), pageSize: 5)
        let engine = InputEngine { code, pageIndex in
            try query.page(for: code, pageIndex: pageIndex)
        }

        var transcript = ""
        for timedEvent in scenario.events {
            let result = engine.process(timedEvent.event)
            if case let .commitText(text) = result.clientAction {
                transcript.append(text)
            }
            if !result.consumed, let passedText = timedEvent.passedText {
                transcript.append(passedText)
            }
        }

        let expectedCycle = "工你来来往往中国输入法你好𠝻,"
        XCTAssertEqual(transcript, String(repeating: expectedCycle, count: 20))
        XCTAssertEqual(transcript.utf8.count, 880)
        XCTAssertEqual(String(format: "%016llx", DictionaryChecksum.fnv1a64(Data(transcript.utf8))),
                       "9ff0a32a41036925")
        XCTAssertEqual(engine.state, .idle)
    }

    private func makeTenMinuteScenario() -> Scenario {
        var events = [TimedEvent]()
        for cycle in 0..<20 {
            let base = cycle * 30
            var raw = [TimedEvent]()
            raw += code("a") + [TimedEvent(second: 0, event: .selectFirst)]
            raw += code("wq") + [TimedEvent(second: 0, event: .selectFirst)]
            raw += code("ggtt") + [TimedEvent(second: 0, event: .select(2))]
            raw += code("khlg") + [TimedEvent(second: 0, event: .selectFirst)]
            raw += code("ltif") + [TimedEvent(second: 0, event: .selectFirst)]
            raw += code("wqx")
            raw += [TimedEvent(second: 0, event: .backspace)]
            raw += code("vb") + [TimedEvent(second: 0, event: .selectFirst)]
            raw += code("adwj")
            raw += [TimedEvent(second: 0, event: .pageNext),
                    TimedEvent(second: 0, event: .selectFirst),
                    TimedEvent(second: 0, event: .passThrough, passedText: ",")]
            raw += code("a") + [TimedEvent(second: 0, event: .cancel)]
            events += raw.enumerated().map {
                TimedEvent(second: base + $0.offset / 2,
                           event: $0.element.event,
                           passedText: $0.element.passedText)
            }
        }
        return Scenario(durationSeconds: 600, events: events)
    }

    private func code(_ value: String) -> [TimedEvent] {
        value.map { TimedEvent(second: 0, event: .letter(String($0))) }
    }
}

private struct Scenario {
    let durationSeconds: Int
    let events: [TimedEvent]
}

private struct TimedEvent {
    let second: Int
    let event: InputEvent
    let passedText: String?

    init(second: Int, event: InputEvent, passedText: String? = nil) {
        self.second = second
        self.event = event
        self.passedText = passedText
    }
}
