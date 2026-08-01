import Foundation
import XCTest

final class InstallationContractTests: XCTestCase {
    func testInstallUpgradeAndBundleReplacementInTemporaryRoot() throws {
        let repository = repositoryRoot()
        let source = temporaryRoot().appendingPathComponent("MacWubi.app")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        try Data("fixture-v1".utf8).write(to: source.appendingPathComponent("Contents/Info.plist"))
        let root = temporaryRoot()
        var environment = ProcessInfo.processInfo.environment
        environment["MACWUBI_TEST_INSTALL_ROOT"] = root.path
        environment["MACWUBI_VERIFY_RELEASE_TOOL"] = "/usr/bin/true"

        try run(repository.appendingPathComponent("Scripts/install.sh"), [source.path], environment)
        let installed = root.appendingPathComponent("MacWubi.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        let firstIdentity = try Data(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))
        try Data("fixture-v2".utf8).write(to: source.appendingPathComponent("Contents/Info.plist"))
        try run(repository.appendingPathComponent("Scripts/upgrade.sh"), [source.path], environment)
        XCTAssertNotEqual(try Data(contentsOf: installed.appendingPathComponent("Contents/Info.plist")),
                          firstIdentity)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .contains { $0.contains("staging") || $0.contains("previous") })
    }

    func testUninstallPreservesDataUnlessDeleteIsExplicit() throws {
        let repository = repositoryRoot()
        let installRoot = temporaryRoot()
        let dataRoot = temporaryRoot()
        try FileManager.default.createDirectory(at: installRoot.appendingPathComponent("MacWubi.app"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try Data("personal".utf8).write(to: dataRoot.appendingPathComponent("Learning"))
        var environment = ProcessInfo.processInfo.environment
        environment["MACWUBI_TEST_INSTALL_ROOT"] = installRoot.path
        environment["MACWUBI_TEST_DATA_ROOT"] = dataRoot.path

        try run(repository.appendingPathComponent("Scripts/uninstall.sh"), [], environment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("MacWubi.app").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataRoot.path))
        try FileManager.default.createDirectory(at: installRoot.appendingPathComponent("MacWubi.app"),
                                                withIntermediateDirectories: true)
        try run(repository.appendingPathComponent("Scripts/uninstall.sh"), ["--delete-data"], environment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataRoot.path))
    }

    private func run(_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let error = Pipe(); process.standardError = error
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0,
                       String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiInstall-\(UUID().uuidString)")
    }
}
