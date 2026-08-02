import XCTest
@testable import MacWubi

final class DiagnosticsRedactionTests: XCTestCase {
    func testDiagnosticsExposeOnlyFixedCategoriesAndCountsForAdversarialSamples() {
        let samples = ["wqvb", "nihaoshijie", "候选正文", "/Users/person/secret.txt",
                       "com.private.application", "2026-08-01T23:00:00 key=a"]
        let counter = DiagnosticCounter()
        for _ in samples { counter.record(.clientOperationFailure) }
        let report = DiagnosticFormatter.report(counter.snapshot())
        XCTAssertEqual(report, "client_operation_failure=6")
        for sample in samples { XCTAssertFalse(report.contains(sample)) }
    }

    func testProductionSourcesContainNoNetworkOrGlobalKeyCaptureAPI() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = repository.appendingPathComponent("Sources", isDirectory: true)
        let prohibited = [
            "URLSession", "NWConnection", "nw_connection", "CFHTTP", "curl_easy",
            "CGEventTap", "CGEvent.tapCreate", "addGlobalMonitorForEventsMatchingMask",
            "IOHIDEventSystemClient"
        ]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))
        var productionSource = ""
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            productionSource += try String(contentsOf: file, encoding: .utf8)
        }
        for symbol in prohibited {
            XCTAssertFalse(productionSource.contains(symbol), "prohibited API: \(symbol)")
        }
    }
}
