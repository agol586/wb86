import Foundation
import XCTest
@testable import MacWubi

@MainActor
final class FilePanelContractTests: XCTestCase {
    func testCancelCreatesNoAccessAndSelectedAccessIsReleased() throws {
        let access = ScopedAccessSpy()
        let cancelled = ImportExportPanelController(
            panels: PanelStub(open: nil, save: nil), scopedAccess: access
        )
        XCTAssertFalse(try cancelled.performImport { _ in XCTFail("must not read") })
        XCTAssertEqual(access.starts, 0)
        XCTAssertEqual(access.stops, 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("fixture".utf8).write(to: url)
        let selected = ImportExportPanelController(
            panels: PanelStub(open: url, save: nil), scopedAccess: access
        )
        XCTAssertTrue(try selected.performImport { XCTAssertEqual($0, Data("fixture".utf8)) })
        XCTAssertEqual(access.starts, 1)
        XCTAssertEqual(access.stops, 1)
    }

    func testFailedExportPreservesExistingDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiExportPreserve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("existing.macwubi")
        try Data("original".utf8).write(to: destination)
        let writer = try SnapshotWriter(rootURL: root.appendingPathComponent("data"))
        let exporter = LexiconExporter(userStore: try UserLexiconStore(writer: writer))
        XCTAssertThrowsError(try exporter.write(Data("replacement".utf8), to: destination) { _ in
            throw TestFailure.expected
        })
        XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
    }

    func testImportReportContainsCountsOnly() {
        let controller = ImportReportViewController()
        controller.present(ImportReport(acceptedCount: 3, mergedCount: 2, skippedCount: 1,
                                        failedCount: 4, errorCategories: [.invalidRecord: 4]))
        XCTAssertEqual(controller.summary, "新增 3，合并 2，跳过 1，失败 4")
        XCTAssertFalse(controller.summary.contains("词条正文"))
    }
}

private struct PanelStub: FilePanelPresenting {
    let open: URL?
    let save: URL?
    func chooseImportURL() -> URL? { open }
    func chooseExportURL() -> URL? { save }
}

private final class ScopedAccessSpy: ScopedResourceAccessing {
    var starts = 0
    var stops = 0
    func start(_ url: URL) -> Bool { starts += 1; return true }
    func stop(_ url: URL) { stops += 1 }
}

private enum TestFailure: Error { case expected }
