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

    func testEveryFullFeatureLookupSampleCompletesWithinTwoMilliseconds() throws {
        let resources = repositoryRoot().appendingPathComponent("Sources/Resources")
        let wb86 = try DictionaryLoader.load(from: resources.appendingPathComponent("wb86.bin"))
        let baseIndex = DictionaryIndex(image: wb86)
        let pinyinImage = try PinyinDictionaryLoader.load(
            from: resources.appendingPathComponent("pinyin-simp.bin"),
            wb86Image: wb86
        )
        let pinyinIndex = PinyinDictionaryIndex(image: pinyinImage)
        let coordinator = PersonalizationCoordinator(
            index: baseIndex,
            pinyinIndex: pinyinIndex,
            userStore: nil,
            learningStore: nil
        )
        let converter = try ScriptConverter(data: Data(
            contentsOf: resources.appendingPathComponent("script-conversion.bin"),
            options: .mappedIfSafe
        ))
        let allEnabled = try InputSettings(
            candidatePageSize: 9,
            candidateLayout: .horizontal,
            candidateFontScale: 2,
            keyBindings: KeyBindingSettings(
                languageSwitch: .standaloneShift,
                scriptSwitch: .controlShiftF,
                widthSwitch: .shiftSpace,
                pageKeyGroups: Set(CandidatePageKeyGroup.allCases),
                keyboardLayout: .us
            ),
            autoCommitAtFour: true,
            autoCommitFirstAtFive: true,
            defaultMode: InputMode(language: .chinese, punctuation: .chinese,
                                   width: .full, script: .traditional),
            automaticFrequency: true,
            mixedPinyinEnabled: true,
            codeHintEnabled: true,
            candidate2And3ShortcutsEnabled: true
        )
        let allEnabledPolicy = allEnabled.candidateRankingPolicy(generation: 99)
        let wubiCode = try XCTUnwrap(InputCode("wqvb"))
        let prefix = try XCTUnwrap(CompositionKeySequence("nih"))
        let predictivePrefix = try XCTUnwrap(CompositionKeySequence("shenm"))
        let exact = try XCTUnwrap(CompositionKeySequence("nihao"))
        let wubiAssociation = try XCTUnwrap(CompositionKeySequence("sm"))
        let largestWubiAssociationRange = try XCTUnwrap(CompositionKeySequence("kh"))

        let duplicateSequence = try XCTUnwrap(CompositionKeySequence("a"))
        let duplicateWubi = [
            try DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "国")
        ]
        let duplicatePinyin = (0..<12).map { index in
            PinyinLookupCandidate(text: index == 0 ? "国" : "测试\(index)",
                                  weight: UInt64(100 - index), baseRank: index,
                                  wubiHint: wubiCode)
        }
        let mixedRanker = CandidateRanker(policy: allEnabledPolicy)

        struct Sample {
            let name: String
            let operation: () throws -> Void
        }
        let samples = [
            Sample(name: "wubi-only") {
                _ = try coordinator.page(for: wubiCode, pageIndex: 0,
                                         policy: allEnabledPolicy)
            },
            Sample(name: "wubi-short-code-association") {
                let result = try coordinator.page(
                    for: wubiAssociation, pageIndex: 0, policy: allEnabledPolicy,
                    mode: allEnabled.defaultMode, mixedPinyinEnabled: false,
                    scriptConverter: converter
                )
                XCTAssertEqual(result.page.items.first?.text, "機")
            },
            Sample(name: "wubi-largest-short-code-association-range") {
                let result = try coordinator.page(
                    for: largestWubiAssociationRange, pageIndex: 0,
                    policy: allEnabledPolicy, mode: allEnabled.defaultMode,
                    mixedPinyinEnabled: false, scriptConverter: converter
                )
                XCTAssertEqual(result.page.items.first?.text, "中")
            },
            Sample(name: "pinyin-prefix") {
                let result = try coordinator.page(
                    for: prefix, pageIndex: 0, policy: allEnabledPolicy,
                    mode: allEnabled.defaultMode, mixedPinyinEnabled: true,
                    scriptConverter: converter
                )
                XCTAssertEqual(result.pinyinState, .viablePrefix)
            },
            Sample(name: "pinyin-prefix-prediction") {
                let result = try coordinator.page(
                    for: predictivePrefix, pageIndex: 0, policy: allEnabledPolicy,
                    mode: allEnabled.defaultMode, mixedPinyinEnabled: true,
                    scriptConverter: converter
                )
                XCTAssertEqual(result.pinyinState, .viablePrefix)
                XCTAssertEqual(result.page.items.first?.text, "什麼")
            },
            Sample(name: "pinyin-exact") {
                let result = try coordinator.page(
                    for: exact, pageIndex: 0, policy: allEnabledPolicy,
                    mode: allEnabled.defaultMode, mixedPinyinEnabled: true,
                    scriptConverter: converter
                )
                XCTAssertEqual(result.pinyinState, .exactMatch)
            },
            Sample(name: "merge-dedupe-traditional-first-page") {
                let page = try mixedRanker.mixedPage(
                    for: duplicateSequence, wubiRecords: duplicateWubi,
                    userEntries: [], pinyinCandidates: duplicatePinyin,
                    learningRecords: [], learningEnabled: true,
                    scriptConverter: converter, outputScript: .traditional, pageIndex: 0
                )
                XCTAssertEqual(Set(page.items.map(\.text)).count, page.items.count)
            },
            Sample(name: "merge-dedupe-traditional-next-page") {
                let page = try mixedRanker.mixedPage(
                    for: duplicateSequence, wubiRecords: duplicateWubi,
                    userEntries: [], pinyinCandidates: duplicatePinyin,
                    learningRecords: [], learningEnabled: true,
                    scriptConverter: converter, outputScript: .traditional, pageIndex: 1
                )
                XCTAssertTrue(page.hasPrevious)
            },
            Sample(name: "all-settings-enabled") {
                _ = try coordinator.page(
                    for: exact, pageIndex: 0, policy: allEnabledPolicy,
                    mode: allEnabled.defaultMode,
                    mixedPinyinEnabled: allEnabled.mixedPinyinEnabled,
                    scriptConverter: converter
                )
            }
        ]

        let warmUpIterations = 20
        let measuredIterations = 100
        var maxima = [String: UInt64]()
        for sample in samples {
            for _ in 0..<warmUpIterations { try sample.operation() }
            for iteration in 0..<measuredIterations {
                let start = DispatchTime.now().uptimeNanoseconds
                try sample.operation()
                let elapsed = DispatchTime.now().uptimeNanoseconds - start
                maxima[sample.name] = max(maxima[sample.name] ?? 0, elapsed)
                XCTAssertLessThan(elapsed, 2_000_000,
                                  "\(sample.name) sample \(iteration) exceeded 2 ms")
            }
        }
        print("MACWUBI_FULL_FEATURE_LOOKUP_MAXIMA " + maxima.keys.sorted().map {
            "\($0)=\(maxima[$0]!)ns"
        }.joined(separator: " "))
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

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension InputSettings {
    func candidateRankingPolicy(generation: UInt64) -> CandidateRankingPolicy {
        CandidateRankingPolicy(settingsGeneration: generation,
                               pageSize: candidatePageSize,
                               automaticFrequency: automaticFrequency)
    }
}
