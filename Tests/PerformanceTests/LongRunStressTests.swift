import Darwin
import Foundation
import XCTest
@testable import MacWubi

final class LongRunStressTests: XCTestCase {
    func testEightHourRapidInputApplicationSwitchAndSessionChurnHarness() throws {
        let durationSeconds = try requestedDurationSeconds()

        let query: InputEngine.Query = { code, pageIndex in
            try CandidatePage(
                items: [Candidate(text: "候选", code: code, source: .base,
                                  baseRank: 0, learnedScore: 0, ordinal: 1)],
                pageIndex: pageIndex, pageSize: 5, totalCount: 1
            )
        }
        let applicationClassCount = 7
        let sampleInterval = min(60.0, max(0.25, durationSeconds / 16.0))
        let deadline = Date().addingTimeInterval(durationSeconds)
        var footprints = [UInt64]()
        var iterations = 0
        var nextSample = Date()

        while Date() < deadline {
            autoreleasepool {
                for applicationIndex in 0..<applicationClassCount {
                    let engine = InputEngine(query: query)
                    for letter in ["w", "q", "v", "b"] { _ = engine.process(.letter(letter)) }
                    if applicationIndex.isMultiple(of: 2) {
                        _ = engine.process(.selectFirst)
                    } else {
                        _ = engine.process(.cancel)
                    }
                    XCTAssertEqual(engine.state, .idle)
                    iterations += 1
                }
            }
            if Date() >= nextSample {
                footprints.append(Self.physicalFootprintBytes())
                nextSample = Date().addingTimeInterval(sampleInterval)
            }
        }
        footprints.append(Self.physicalFootprintBytes())

        XCTAssertGreaterThan(iterations, 0)
        XCTAssertGreaterThanOrEqual(footprints.count, 2)
        let warmIndex = max(0, footprints.count / 4)
        let steady = Array(footprints[warmIndex...])
        let firstWindow = steady.prefix(max(1, steady.count / 4))
        let lastWindow = steady.suffix(max(1, steady.count / 4))
        let firstAverage = firstWindow.reduce(0, +) / UInt64(firstWindow.count)
        let lastAverage = lastWindow.reduce(0, +) / UInt64(lastWindow.count)
        let allowedDrift: UInt64 = 1_048_576
        print("MACWUBI_STRESS_REPORT durationSeconds=\(durationSeconds) iterations=\(iterations) "
              + "samples=\(footprints.count) firstSteadyBytes=\(firstAverage) "
              + "lastSteadyBytes=\(lastAverage) allowedDriftBytes=\(allowedDrift)")
        XCTAssertLessThanOrEqual(lastAverage, firstAverage + allowedDrift,
                                 "physical footprint shows sustained growth")
    }

    private func requestedDurationSeconds() throws -> TimeInterval {
        if let value = ProcessInfo.processInfo.environment["MACWUBI_LONG_RUN_SECONDS"],
           let seconds = TimeInterval(value), seconds > 0 {
            return seconds
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = repositoryRoot.appendingPathComponent(".build/long-run-duration")
        if let value = try? String(contentsOf: configuration, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let seconds = TimeInterval(value), seconds > 0 {
            return seconds
        }
        return 2
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
