import Darwin
import Foundation
import XCTest
@testable import MacWubi

final class LongRunStressTests: XCTestCase {
    func testOneMonthEquivalentMillionCharacterWorkloadHarness() throws {
        let targetCommittedCharacters = try requestedCommittedCharacterTarget()
        let query: InputEngine.SequencePolicyQuery = { sequence, pageIndex, policy, mode, mixed in
            let isPinyin = mixed && ["nihao", "shi"].contains { $0.hasPrefix(sequence.letters) }
            let exactPinyin = ["nihao", "shi"].contains(sequence.letters)
            let queryKey = isPinyin && exactPinyin
                ? CandidateQueryKey(kind: .pinyin, code: sequence.letters)!
                : sequence.wubiCode.map(CandidateQueryKey.wubi)
            let totalCount = queryKey == nil ? 0 : 12
            let start = pageIndex * policy.pageSize
            let end = min(start + policy.pageSize, totalCount)
            let items: [Candidate]
            if let queryKey, start < end {
                items = try (start..<end).enumerated().map { offset, rank in
                    try Candidate(text: mode.script == .traditional ? "測試\(rank)" : "测试\(rank)",
                                  queryKey: queryKey,
                                  source: queryKey.kind == .pinyin ? .localPinyin : .baseWubi,
                                  baseRank: rank, learnedScore: policy.automaticFrequency ? rank : 0,
                                  ordinal: offset + 1)
                }
            } else {
                items = []
            }
            return SequenceQueryResult(
                pinyinState: isPinyin
                    ? (exactPinyin ? .exactMatch : .viablePrefix) : .unavailable,
                page: try CandidatePage(items: items, pageIndex: pageIndex,
                                        pageSize: policy.pageSize, totalCount: totalCount)
            )
        }
        let applicationClassCount = 8
        let logicalDayCount = 30
        let makeEngines = {
            (0..<applicationClassCount).map { _ in InputEngine(sequencePolicyQuery: query) }
        }
        // Prime the engine and candidate construction paths before establishing the first
        // steady-state memory/latency window. The separate release lookup benchmark owns the
        // every-sample 2 ms gate; this harness detects sustained growth over monthly volume.
        for engine in makeEngines() {
            var settings = InputSettings.newInstallDefault
            settings.automaticFrequency = true
            settings.mixedPinyinEnabled = true
            engine.apply(settings: settings, generation: 1)
            for letter in ["n", "i", "h", "a", "o"] {
                _ = engine.process(.letter(letter))
            }
            _ = engine.process(.selectFirst)
            _ = engine.process(.cancel)
        }
        var footprints = [Self.physicalFootprintBytes()]
        var firstLatencySum: UInt64 = 0
        var firstLatencyCount: UInt64 = 0
        var lastLatencySum: UInt64 = 0
        var lastLatencyCount: UInt64 = 0
        var maximumLatency: UInt64 = 0
        var iterations = 0
        var learningDeltaCount = 0
        var committedCharacters = 0

        for logicalDay in 1...logicalDayCount {
            let engines = makeEngines()
            let dayTarget = (targetCommittedCharacters * logicalDay + logicalDayCount - 1)
                / logicalDayCount
            while committedCharacters < dayTarget {
                autoreleasepool {
                    for (applicationIndex, engine) in engines.enumerated() {
                        var settings = InputSettings.newInstallDefault
                        settings.candidatePageSize = 5 + iterations % 5
                        settings.automaticFrequency = true
                        settings.mixedPinyinEnabled = true
                        settings.autoCommitAtFour = iterations.isMultiple(of: 2)
                        settings.autoCommitFirstAtFive = iterations.isMultiple(of: 3)
                        settings.defaultMode.script = iterations.isMultiple(of: 2)
                            ? .simplified : .traditional
                        settings.keyBindings.pageKeyGroups = Set(CandidatePageKeyGroup.allCases)
                        engine.initializeMode(from: settings.defaultMode)
                        engine.apply(settings: settings, generation: UInt64(iterations + 1))
                        let keys: [String]
                        switch (iterations + applicationIndex) % 3 {
                        case 0: keys = ["w", "q", "v", "b"]
                        case 1: keys = ["n", "i", "h", "a", "o"]
                        default: keys = ["s", "h", "i"]
                        }
                        for letter in keys {
                            let start = DispatchTime.now().uptimeNanoseconds
                            let result = engine.process(.letter(letter))
                            let latency = DispatchTime.now().uptimeNanoseconds - start
                            maximumLatency = max(maximumLatency, latency)
                            if committedCharacters <= targetCommittedCharacters / 4 {
                                firstLatencySum += latency
                                firstLatencyCount += 1
                            } else if committedCharacters >= targetCommittedCharacters * 3 / 4 {
                                lastLatencySum += latency
                                lastLatencyCount += 1
                            }
                            committedCharacters += Self.chineseCharacterCount(in: result)
                        }
                        committedCharacters += Self.chineseCharacterCount(in: engine.process(.pageNext))
                        committedCharacters += Self.chineseCharacterCount(in: engine.process(.pagePrevious))
                        let selected = engine.process(.selectFirst)
                        committedCharacters += Self.chineseCharacterCount(in: selected)
                        if selected.learningDelta != nil { learningDeltaCount += 1 }
                        committedCharacters += Self.chineseCharacterCount(in: engine.process(.cancel))
                        XCTAssertEqual(engine.state, .idle)
                        iterations += 1
                    }
                }
            }
            footprints.append(Self.physicalFootprintBytes())
        }

        XCTAssertGreaterThan(iterations, 0)
        XCTAssertGreaterThan(learningDeltaCount, 0)
        XCTAssertGreaterThanOrEqual(committedCharacters, targetCommittedCharacters)
        XCTAssertEqual(footprints.count, logicalDayCount + 1)
        let warmIndex = max(0, footprints.count / 4)
        let steady = Array(footprints[warmIndex...])
        let firstWindow = steady.prefix(max(1, steady.count / 4))
        let lastWindow = steady.suffix(max(1, steady.count / 4))
        let firstAverage = firstWindow.reduce(0, +) / UInt64(firstWindow.count)
        let lastAverage = lastWindow.reduce(0, +) / UInt64(lastWindow.count)
        let allowedDrift: UInt64 = 1_048_576
        XCTAssertGreaterThan(firstLatencyCount, 0)
        XCTAssertGreaterThan(lastLatencyCount, 0)
        let firstLatency = firstLatencySum / firstLatencyCount
        let lastLatency = lastLatencySum / lastLatencyCount
        print("MACWUBI_MONTHLY_VOLUME_TEST targetCommittedCharacters=\(targetCommittedCharacters) "
              + "committedCharacters=\(committedCharacters) logicalDays=\(logicalDayCount) "
              + "iterations=\(iterations) samples=\(footprints.count) firstSteadyBytes=\(firstAverage) "
              + "lastSteadyBytes=\(lastAverage) allowedDriftBytes=\(allowedDrift) "
              + "firstLatencyNs=\(firstLatency) lastLatencyNs=\(lastLatency) "
              + "maximumLatencyNs=\(maximumLatency) learningDeltas=\(learningDeltaCount)")
        XCTAssertLessThanOrEqual(lastAverage, firstAverage + allowedDrift,
                                 "physical footprint shows sustained growth")
        XCTAssertLessThanOrEqual(lastLatency, firstLatency + 200_000,
                                 "recognized lookup latency shows sustained growth")
    }

    private func requestedCommittedCharacterTarget() throws -> Int {
        if let value = ProcessInfo.processInfo.environment["MACWUBI_MONTHLY_VOLUME_CHARACTERS"],
           let characters = Int(value), characters > 0 {
            return characters
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = repositoryRoot.appendingPathComponent(".build/monthly-volume-characters")
        if let value = try? String(contentsOf: configuration, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let characters = Int(value), characters > 0 {
            return characters
        }
        return 3_000
    }

    private static func chineseCharacterCount(in result: InputProcessingResult) -> Int {
        result.clientActions.actions.reduce(into: 0) { count, action in
            guard case let .commitText(text) = action else { return }
            count += text.reduce(into: 0) { characterCount, character in
                if character.unicodeScalars.contains(where: isHanScalar) { characterCount += 1 }
            }
        }
    }

    private static func isHanScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2EBEF,
             0x30000...0x323AF:
            return true
        default:
            return false
        }
    }

    private static func physicalFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size)
            / mach_msg_type_number_t(MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
