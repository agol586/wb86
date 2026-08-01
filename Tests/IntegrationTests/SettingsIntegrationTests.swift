import Foundation
import XCTest
@testable import MacWubi

final class SettingsIntegrationTests: XCTestCase {
    func testEverySettingPersistsAppliesAndRestoresWithoutPersonalizationLoss() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSettingsFlow-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        let code = try XCTUnwrap(InputCode("wqvb"))
        try UserLexiconStore(writer: writer).upsert(code: code, text: "用户词",
                                                         fixedRank: 1, createdBy: .manual)
        try LearningStore(writer: writer).recordSelection(code: code,
                                                          candidateText: "学习词", amount: 3)
        let userBefore = try Data(contentsOf: writer.currentURL(for: .userLexicon))
        let learningBefore = try Data(contentsOf: writer.currentURL(for: .learning))

        let store = try SettingsStore(writer: writer)
        var globallyApplied = [InputSettings]()
        let coordinator = SettingsCoordinator(store: store) { globallyApplied.append($0) }
        let session = SettingsIntegrationSession()
        coordinator.register(session)
        session.applied.removeAll()

        let changed = try InputSettings(
            candidatePageSize: 9,
            candidateLayout: .horizontal,
            candidateFontScale: 1.6,
            keyBindings: KeyBindingSettings(modeSwitch: .disabled, pageKeys: .bracketPair),
            autoCommitAtFour: true,
            defaultMode: InputMode(language: .directEnglish, punctuation: .english,
                                   width: .full, script: .traditional),
            learningEnabled: false
        )
        try coordinator.save(changed)

        XCTAssertEqual(session.applied, [changed])
        XCTAssertEqual(globallyApplied, [changed])
        XCTAssertEqual(try SettingsStore(writer: SnapshotWriter(rootURL: root)).settings, changed)
        let preview = CandidateAppearanceController().preview(settings: changed)
        XCTAssertEqual(preview.layout, .horizontal)
        XCTAssertEqual(preview.fontScale, 1.6)

        try coordinator.restoreDefaults()
        XCTAssertEqual(try SettingsStore(writer: SnapshotWriter(rootURL: root)).settings, .default)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .userLexicon)), userBefore)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .learning)), learningBefore)
    }
}

private final class SettingsIntegrationSession: SettingsSessionControlling {
    var state = CompositionState.idle
    var applied = [InputSettings]()
    func apply(settings: InputSettings) { applied.append(settings) }
}
