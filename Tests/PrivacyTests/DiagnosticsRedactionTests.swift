import XCTest
@testable import MacWubi

final class DiagnosticsRedactionTests: XCTestCase {
    func testDiagnosticsExposeOnlyFixedCategoriesAndCountsForAdversarialSamples() {
        let samples = ["wqvb", "候选正文", "/Users/person/secret.txt",
                       "com.private.application", "2026-08-01T23:00:00 key=a"]
        let counter = DiagnosticCounter()
        for _ in samples { counter.record(.clientOperationFailure) }
        let report = DiagnosticFormatter.report(counter.snapshot())
        XCTAssertEqual(report, "client_operation_failure=5")
        for sample in samples { XCTAssertFalse(report.contains(sample)) }
    }
}
