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

    func testSharedMappedPinyinIndexKeepsSessionPoliciesAndRecordsPinyinSelection() throws {
        let resources = try bundledMixedResources()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiMixedDaily-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let learning = try LearningStore(writer: SnapshotWriter(rootURL: root))
        let coordinator = PersonalizationCoordinator(
            index: resources.wubiIndex,
            pinyinIndex: resources.pinyinIndex,
            userStore: nil,
            learningStore: learning
        )
        XCTAssertTrue(coordinator.hasLocalPinyin)
        let sequenceQuery: InputEngine.SequencePolicyQuery = {
            sequence, pageIndex, policy, mode, mixed in
            try coordinator.page(
                for: sequence, pageIndex: pageIndex, policy: policy, mode: mode,
                mixedPinyinEnabled: mixed, scriptConverter: resources.converter
            )
        }
        let compact = InputEngine(sequencePolicyQuery: sequenceQuery)
        let roomy = InputEngine(sequencePolicyQuery: sequenceQuery)
        var compactSettings = InputSettings.default
        compactSettings.candidatePageSize = 5
        compactSettings.autoCommitAtFour = false
        compactSettings.mixedPinyinEnabled = true
        compactSettings.automaticFrequency = true
        var roomySettings = compactSettings
        roomySettings.candidatePageSize = 9
        compact.apply(settings: compactSettings, generation: 7)
        roomy.apply(settings: roomySettings, generation: 8)

        for letter in ["n", "i"] {
            _ = compact.process(.letter(letter))
            _ = roomy.process(.letter(letter))
        }
        XCTAssertEqual(compact.state.composition?.candidates.pageSize, 5)
        XCTAssertEqual(roomy.state.composition?.candidates.pageSize, 9)
        XCTAssertEqual(compact.rankingPolicy.settingsGeneration, 7)
        XCTAssertEqual(roomy.rankingPolicy.settingsGeneration, 8)

        compact.reset()
        for letter in ["n", "i", "h", "a", "o"] {
            _ = compact.process(.letter(letter))
        }
        let selectedText = try XCTUnwrap(compact.state.composition?.candidates.items.first?.text)
        let selection = compact.process(.selectFirst)
        let delta = try XCTUnwrap(selection.learningDelta)
        XCTAssertEqual(delta.queryKey.kind, .pinyin)
        XCTAssertEqual(delta.queryKey.normalizedCode, "nihao")
        XCTAssertEqual(delta.candidateText, selectedText)
        coordinator.record(delta, policy: compact.rankingPolicy)

        let learningKey = try LearningKey(queryKey: delta.queryKey,
                                          candidateText: delta.candidateText)
        XCTAssertEqual(learning.score(key: learningKey), 1)
    }

    func testUnavailablePinyinResourceFallsBackToSharedWB86WithoutNetworkRecovery() throws {
        let resources = try bundledMixedResources()
        let coordinator = PersonalizationCoordinator(
            index: resources.wubiIndex,
            pinyinIndex: nil,
            userStore: nil,
            learningStore: nil
        )
        let engine = InputEngine(sequencePolicyQuery: {
            sequence, pageIndex, policy, mode, mixed in
            try coordinator.page(
                for: sequence, pageIndex: pageIndex, policy: policy, mode: mode,
                mixedPinyinEnabled: mixed, scriptConverter: resources.converter
            )
        })
        var settings = InputSettings.default
        settings.mixedPinyinEnabled = true
        settings.autoCommitAtFour = false
        engine.apply(settings: settings)

        _ = engine.process(.letter("w"))
        let result = engine.process(.letter("q"))

        XCTAssertFalse(coordinator.hasLocalPinyin)
        XCTAssertEqual(result.state.composition?.route, .wubiOnly)
        XCTAssertFalse(result.state.composition?.candidates.items.isEmpty ?? true)
        XCTAssertEqual(result.state.composition?.candidates.items.first?.source, .baseWubi)
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

    private func bundledMixedResources() throws
        -> (wubiIndex: DictionaryIndex, pinyinIndex: PinyinDictionaryIndex,
            converter: ScriptConverter) {
        let bundle = Bundle.main
        let wb86URL = try XCTUnwrap(bundle.url(forResource: "wb86", withExtension: "bin"))
        let pinyinURL = try XCTUnwrap(
            bundle.url(forResource: "pinyin-simp", withExtension: "bin")
        )
        let conversionURL = try XCTUnwrap(
            bundle.url(forResource: "script-conversion", withExtension: "bin")
        )
        let wb86Image = try DictionaryLoader.load(from: wb86URL)
        let pinyinImage = try PinyinDictionaryLoader.load(from: pinyinURL,
                                                          wb86Image: wb86Image)
        return (
            DictionaryIndex(image: wb86Image),
            PinyinDictionaryIndex(image: pinyinImage),
            try ScriptConverter(data: Data(contentsOf: conversionURL, options: .mappedIfSafe))
        )
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
