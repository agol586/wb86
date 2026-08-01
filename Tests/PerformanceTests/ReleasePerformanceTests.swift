import Darwin
import Foundation
import XCTest
@testable import MacWubi

final class ReleasePerformanceTests: XCTestCase {
    func testReleaseLookupCorpusReportsAbsoluteLatencyAndStaysBelowBudget() throws {
        let records = try acceptanceRecords()
        let image = try DictionaryFormatV1.encode(records: records, buildIdentifier: 1)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiReleasePerformance-\(UUID().uuidString)")
        try image.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let query = CandidateQuery(index: DictionaryIndex(image: try DictionaryLoader.load(from: url)),
                                   pageSize: 5)
        let codes = Set(records.map(\.code)).sorted()
        let warmUpIterations = 20
        let samplesPerCode = 100

        for _ in 0..<warmUpIterations {
            for code in codes { _ = try query.page(for: code, pageIndex: 0) }
        }

        var nanoseconds = [UInt64]()
        nanoseconds.reserveCapacity(codes.count * samplesPerCode)
        for code in codes {
            for _ in 0..<samplesPerCode {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try query.page(for: code, pageIndex: 0)
                nanoseconds.append(DispatchTime.now().uptimeNanoseconds - start)
            }
        }

        let report = ReleaseLookupReport(
            samplesNanoseconds: nanoseconds,
            codeCount: codes.count,
            recordCount: records.count,
            warmUpIterations: warmUpIterations,
            samplesPerCode: samplesPerCode
        )
        print(report.rendered)
        XCTAssertEqual(report.sampleCount, codes.count * samplesPerCode)
        XCTAssertLessThan(report.maximumNanoseconds, 2_000_000,
                          "every release lookup sample must complete in under 2 ms")
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

private struct ReleaseLookupReport {
    let samplesNanoseconds: [UInt64]
    let codeCount: Int
    let recordCount: Int
    let warmUpIterations: Int
    let samplesPerCode: Int

    var sampleCount: Int { samplesNanoseconds.count }
    var maximumNanoseconds: UInt64 { samplesNanoseconds.max() ?? 0 }

    var rendered: String {
        let sorted = samplesNanoseconds.sorted()
        let process = ProcessInfo.processInfo
        return """
        MACWUBI_PERFORMANCE_REPORT
        architecture=\(machineArchitecture())
        hardware=\(process.hostName.isEmpty ? "unknown" : machineModel())
        macOS=\(process.operatingSystemVersionString)
        processorCount=\(process.processorCount)
        physicalMemoryBytes=\(process.physicalMemory)
        configuration=\(buildConfiguration)
        clock=DispatchTime.uptimeNanoseconds
        corpus=wb86-acceptance.tsv
        corpusRecords=\(recordCount)
        corpusCodes=\(codeCount)
        warmUpIterationsPerCorpus=\(warmUpIterations)
        samplesPerCode=\(samplesPerCode)
        sampleCount=\(sampleCount)
        p50Nanoseconds=\(percentile(sorted, 0.50))
        p95Nanoseconds=\(percentile(sorted, 0.95))
        p99Nanoseconds=\(percentile(sorted, 0.99))
        maximumNanoseconds=\(maximumNanoseconds)
        budgetNanoseconds=2000000
        """
    }

    private var buildConfiguration: String {
#if DEBUG
        "Debug"
#else
        "Release"
#endif
    }

    private func percentile(_ sorted: [UInt64], _ fraction: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * fraction)) - 1)
        return sorted[max(0, index)]
    }

    private func machineArchitecture() -> String {
        var value = utsname()
        uname(&value)
        return withUnsafePointer(to: &value.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private func machineModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }
}
