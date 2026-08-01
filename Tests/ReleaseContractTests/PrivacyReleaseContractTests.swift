import Foundation
import XCTest

final class PrivacyReleaseContractTests: XCTestCase {
    func testNoNetworkEntitlementsFrameworksOrSymbols() throws {
        let executable = Bundle.main.executableURL!
        let dependencies = try run("/usr/bin/otool", ["-L", executable.path])
        for prohibited in ["CFNetwork", "Network.framework", "WebKit", "libcurl"] {
            XCTAssertFalse(dependencies.contains(prohibited), prohibited)
        }
        let entitlements = try run("/usr/bin/codesign", ["--display", "--entitlements", ":-",
                                                            Bundle.main.bundleURL.path], allowFailure: true)
        for prohibited in ["network.client", "network.server", "application-groups"] {
            XCTAssertFalse(entitlements.contains(prohibited), prohibited)
        }

        let declaredEntitlements = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/Supporting/MacWubi.entitlements"
            ), encoding: .utf8
        )
        for prohibited in ["network.client", "network.server", "application-groups",
                           "temporary-exception.mach"] {
            XCTAssertFalse(declaredEntitlements.contains(prohibited), prohibited)
        }
        // Xcode injects testmanager Mach exceptions into its hosted XCTest copy. Those are not
        // product entitlements; the checked-in declaration and standalone release audit remain empty.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            XCTAssertFalse(entitlements.contains("temporary-exception.mach"))
        }

        let sourceRoot = repositoryRoot().appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: sourceRoot,
                                                        includingPropertiesForKeys: nil)!
        let source = try enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        for prohibited in ["import Network", "import CFNetwork", "URLSession(", "NWConnection("] {
            XCTAssertFalse(source.contains(prohibited), prohibited)
        }
    }

    private func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run(); process.waitUntilExit()
        if !allowFailure { XCTAssertEqual(process.terminationStatus, 0) }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
