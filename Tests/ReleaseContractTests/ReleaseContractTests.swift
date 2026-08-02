import Foundation
import XCTest

final class ReleaseContractTests: XCTestCase {
    func testHostExecutableIsExactlyArm64() throws {
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let header = try Data(contentsOf: executable, options: .mappedIfSafe)
        XCTAssertGreaterThanOrEqual(header.count, 8)
        XCTAssertEqual(readUInt32LittleEndian(header, at: 0), 0xfeed_facf, "must be a thin 64-bit Mach-O")
        XCTAssertEqual(readUInt32LittleEndian(header, at: 4), 0x0100_000c, "must be CPU_TYPE_ARM64")
    }

    func testBundleHasRequiredInputMethodMetadata() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "org.macwubi.inputmethod.MacWubi")
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertNil(info["LSBackgroundOnly"],
                     "an input method that owns a settings window cannot be background-only")
        XCTAssertEqual(
            info["InputMethodConnectionName"] as? String,
            "org.macwubi.inputmethod.MacWubi_Connection"
        )
        XCTAssertFalse((info["InputMethodServerControllerClass"] as? String ?? "").isEmpty)
        XCTAssertNotNil(info["tsInputMethodCharacterRepertoireKey"])
        XCTAssertEqual(info["TISInputSourceID"] as? String, "org.macwubi.inputmethod.MacWubi")
        XCTAssertEqual(info["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertNil(info["ComponentInputModeDict"], "single system source must be directly selectable")
        XCTAssertNotNil(NSClassFromString("MacWubi.InputController"))
    }

    func testProjectSupportsOnlyNativeArm64AndHasNoPackageManagerDependency() throws {
        let root = repositoryRoot()
        let project = try String(
            contentsOf: root.appendingPathComponent("MacWubi.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("ARCHS = arm64;"))
        XCTAssertFalse(project.contains("x86_64"))
        XCTAssertFalse(project.contains("XCRemoteSwiftPackageReference"))
        XCTAssertFalse(project.contains("XCSwiftPackageProductDependency"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Package.swift").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("MacWubi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").path
        ))
    }

    func testPinyinManifestProvenanceAndLicenseShipInBundle() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        for path in [
            "pinyin-simp.bin", "pinyin-simp.manifest.json",
            "rime-pinyin-simp/LICENSE", "rime-pinyin-simp/AUTHORS",
            "rime-pinyin-simp/SOURCE.md"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: resources.appendingPathComponent(path).path
            ), "missing bundled resource: \(path)")
        }
        let manifestData = try Data(
            contentsOf: resources.appendingPathComponent("pinyin-simp.manifest.json")
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        XCTAssertEqual(manifest["format"] as? String, "MWPY")
        XCTAssertEqual(manifest["licenseIdentifier"] as? String, "Apache-2.0")
        XCTAssertEqual(manifest["sourceRevision"] as? String,
                       "0c6861ef7420ee780270ca6d993d18d4101049d0")
        let license = try String(
            contentsOf: resources.appendingPathComponent("rime-pinyin-simp/LICENSE"),
            encoding: .utf8
        )
        XCTAssertTrue(license.contains("Apache License"))
    }

    func testBundleIsSignedAndUsesOnlyApprovedEntitlements() throws {
        let bundleURL = Bundle.main.bundleURL
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundleURL.path])
        let raw = try run("/usr/bin/codesign", ["--display", "--entitlements", ":-", bundleURL.path],
                          mergeStandardError: true)
        let xml = try XCTUnwrap(raw.range(of: "<?xml")).lowerBound
        let data = Data(raw[xml...].utf8)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNil(entitlements["com.apple.security.app-sandbox"])
        XCTAssertNil(entitlements["com.apple.security.files.user-selected.read-write"])
        XCTAssertNil(entitlements["com.apple.security.temporary-exception.mach-register.global-name"])
        // Xcode injects these lookup exceptions into its test host. The standalone Release bundle
        // is checked strictly by Scripts/verify-release.sh and must contain none of them.
        if let testHostLookups = entitlements[
            "com.apple.security.temporary-exception.mach-lookup.global-name"
        ] as? [String] {
            XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"])
            XCTAssertEqual(
                Set(testHostLookups),
                Set(["com.apple.testmanagerd", "com.apple.dt.testmanagerd.runner", "com.apple.coresymbolicationd"])
            )
        }
        XCTAssertNil(entitlements["com.apple.security.network.client"])
        XCTAssertNil(entitlements["com.apple.security.network.server"])
        XCTAssertNil(entitlements["com.apple.security.automation.apple-events"])
        XCTAssertNil(entitlements["com.apple.security.application-groups"])

    }

    private func run(_ executable: String, _ arguments: [String],
                     mergeStandardError: Bool = false) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        if mergeStandardError {
            process.standardError = output
        }
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ReleaseContractTests", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }

    private func readUInt32LittleEndian(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { value, byteIndex in
            value | (UInt32(data[offset + byteIndex]) << UInt32(byteIndex * 8))
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
