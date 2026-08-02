import AppKit
import Foundation
import XCTest
@testable import MacWubi

@MainActor
final class SettingsIntegrationTests: XCTestCase {
    func testMultipleClientsFinishAndReactivateTheirSettingsGenerationsIndependently() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiIndependentSessions-\(UUID().uuidString)")
        let coordinator = SettingsCoordinator(
            store: try SettingsStore(writer: SnapshotWriter(rootURL: root))
        )
        let first = InputControllerSession(
            engine: InputEngine { code, page in
                try CandidatePage(items: [], pageIndex: page, pageSize: 5, totalCount: 0)
            },
            presenter: SettingsAppearancePresenter()
        )
        let second = InputControllerSession(
            engine: InputEngine { code, page in
                try CandidatePage(items: [], pageIndex: page, pageSize: 5, totalCount: 0)
            },
            presenter: SettingsAppearancePresenter()
        )
        let firstClient = SettingsInputClient()
        let secondClient = SettingsInputClient()
        coordinator.register(first)
        coordinator.register(second)

        _ = first.handle(.switchWidth, client: firstClient)
        _ = second.handle(.switchScript, client: secondClient)
        _ = first.handle(.letter("a"), client: firstClient)
        _ = second.handle(.letter("b"), client: secondClient)

        var changed = InputSettings.default
        changed.defaultMode = InputMode(language: .directEnglish, punctuation: .english,
                                        width: .half, script: .traditional)
        changed.candidatePageSize = 9
        try coordinator.save(changed)

        first.deactivate(client: firstClient)
        XCTAssertEqual(first.activeSnapshot.generation, 1)
        XCTAssertEqual(second.activeSnapshot.generation, 0)
        XCTAssertEqual(second.pendingSnapshot?.generation, 1)
        XCTAssertEqual(firstClient.clearCount, 1)
        XCTAssertEqual(secondClient.clearCount, 0)

        first.reactivate()
        XCTAssertEqual(first.mode, changed.defaultMode)
        XCTAssertEqual(second.mode.language, .chinese)
        XCTAssertEqual(second.mode.script, .traditional)

        _ = second.handle(.cancel, client: secondClient)
        XCTAssertEqual(second.activeSnapshot.generation, 1)
        XCTAssertNil(second.pendingSnapshot)
        XCTAssertEqual(secondClient.clearCount, 1)
        XCTAssertEqual(second.mode.language, .chinese)
        XCTAssertEqual(second.mode.script, .traditional)

        second.reactivate()
        XCTAssertEqual(second.mode, changed.defaultMode)
        XCTAssertEqual(first.activeSnapshot.generation, 1)
    }

    func testAppearanceAppliesImmediatelyWhileSemanticSnapshotWaitsAndModeStaysTemporary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiAppearanceDelay-\(UUID().uuidString)")
        let coordinator = SettingsCoordinator(
            store: try SettingsStore(writer: SnapshotWriter(rootURL: root))
        )
        let presenter = SettingsAppearancePresenter()
        let engine = InputEngine { code, page in
            try CandidatePage(items: [], pageIndex: page, pageSize: 5, totalCount: 0)
        }
        let session = InputControllerSession(engine: engine, presenter: presenter)
        let client = SettingsInputClient()
        coordinator.register(session)
        _ = session.handle(.switchWidth, client: client)
        XCTAssertEqual(session.mode.width, .full)
        _ = session.handle(.letter("a"), client: client)
        XCTAssertEqual(session.state.kind, .composing)

        var changed = InputSettings.default
        changed.candidateLayout = .horizontal
        changed.candidateFontScale = 1.5
        changed.defaultMode.width = .half
        changed.defaultMode.script = .traditional
        try coordinator.save(changed)

        XCTAssertEqual(session.appearanceSettings.candidateLayout, .horizontal)
        XCTAssertEqual(presenter.applied.last?.candidateFontScale, 1.5)
        XCTAssertEqual(session.activeSnapshot.generation, 0)
        XCTAssertEqual(session.pendingSnapshot?.generation, 1)
        XCTAssertEqual(session.mode.width, .full)

        _ = session.handle(.cancel, client: client)
        XCTAssertEqual(session.activeSnapshot.generation, 1)
        XCTAssertNil(session.pendingSnapshot)
        XCTAssertEqual(session.mode.width, .full)

        let newSession = InputControllerSession(
            engine: InputEngine { code, page in
                try CandidatePage(items: [], pageIndex: page, pageSize: 5, totalCount: 0)
            },
            presenter: SettingsAppearancePresenter()
        )
        coordinator.register(newSession)
        XCTAssertEqual(newSession.mode, changed.defaultMode)
    }

    func testAutoCommitAndFrequencyPersistButWaitForCompositionSafeBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiAutoPolicyDelay-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        let coordinator = SettingsCoordinator(store: try SettingsStore(writer: writer))
        let session = InputControllerSession(
            engine: InputEngine { _, page in
                try CandidatePage(items: [], pageIndex: page, pageSize: 5, totalCount: 0)
            },
            presenter: SettingsAppearancePresenter()
        )
        let client = SettingsInputClient()
        coordinator.register(session)
        _ = session.handle(.letter("a"), client: client)
        XCTAssertEqual(session.state.kind, .composing)

        var changed = InputSettings.newInstallDefault
        changed.autoCommitAtFour = false
        changed.autoCommitFirstAtFive = true
        changed.automaticFrequency = true
        try coordinator.save(changed)

        XCTAssertTrue(session.activeSnapshot.settings.autoCommitAtFour)
        XCTAssertFalse(session.activeSnapshot.settings.autoCommitFirstAtFive)
        XCTAssertFalse(session.activeSnapshot.settings.automaticFrequency)
        XCTAssertEqual(session.pendingSnapshot?.settings, changed)

        let restarted = try SettingsStore(writer: SnapshotWriter(rootURL: root))
        XCTAssertEqual(restarted.settings, changed)
        XCTAssertEqual(restarted.snapshot.generation, 1)

        _ = session.handle(.cancel, client: client)
        XCTAssertEqual(session.state.kind, .idle)
        XCTAssertNil(session.pendingSnapshot)
        XCTAssertEqual(session.activeSnapshot.settings, changed)
    }

    func testSessionsFreezeActiveSnapshotAndKeepOnlyLatestPendingGeneration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSessionSnapshots-\(UUID().uuidString)")
        let store = try SettingsStore(writer: SnapshotWriter(rootURL: root))
        let coordinator = SettingsCoordinator(store: store)
        let idle = SettingsIntegrationSession()
        let composing = SettingsIntegrationSession()
        composing.state = try .composing(
            code: XCTUnwrap(InputCode("a")),
            candidates: CandidatePage(items: [], pageIndex: 0, pageSize: 5, totalCount: 0),
            pageIndex: 0,
            selectionIndex: nil
        )
        coordinator.register(idle)
        coordinator.register(composing)

        var first = InputSettings.default
        first.candidatePageSize = 7
        try coordinator.save(first)
        XCTAssertEqual(idle.activeSnapshot.generation, 1)
        XCTAssertNil(idle.pendingSnapshot)
        XCTAssertEqual(composing.activeSnapshot.generation, 0)
        XCTAssertEqual(composing.pendingSnapshot?.generation, 1)

        var latest = first
        latest.candidatePageSize = 9
        try coordinator.save(latest)
        XCTAssertEqual(idle.activeSnapshot, SettingsSnapshot(generation: 2, settings: latest))
        XCTAssertEqual(composing.pendingSnapshot,
                       SettingsSnapshot(generation: 2, settings: latest))

        composing.state = .idle
        coordinator.applyPendingAtIdle()
        XCTAssertEqual(composing.activeSnapshot,
                       SettingsSnapshot(generation: 2, settings: latest))
        XCTAssertNil(composing.pendingSnapshot)

        let newSession = SettingsIntegrationSession()
        coordinator.register(newSession)
        XCTAssertEqual(newSession.activeSnapshot,
                       SettingsSnapshot(generation: 2, settings: latest))
    }

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

    func testRestoreConfirmationCancelFailureAndSuccessAreSettingsOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiRestoreTransaction-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        let code = try XCTUnwrap(InputCode("wqvb"))
        try UserLexiconStore(writer: writer).upsert(code: code, text: "用户词",
                                                  fixedRank: 2, createdBy: .manual)
        try LearningStore(writer: writer).recordSelection(code: code,
                                                          candidateText: "学习词", amount: 2)
        let store = try SettingsStore(writer: writer)
        var changed = InputSettings.default
        changed.candidatePageSize = 9
        changed.defaultMode.script = .traditional
        try store.save(changed)
        let coordinator = SettingsCoordinator(store: store)
        let session = SettingsIntegrationSession()
        coordinator.register(session)
        session.applied.removeAll()
        let controller = SettingsWindowController(settings: store.settings) {
            try coordinator.save($0)
        }
        controller.loadWindow()

        let settingsBefore = try Data(contentsOf: writer.currentURL(for: .settings))
        let userBefore = try Data(contentsOf: writer.currentURL(for: .userLexicon))
        let learningBefore = try Data(contentsOf: writer.currentURL(for: .learning))
        let userGeneration = try writer.load(.userLexicon)?.generation
        let learningGeneration = try writer.load(.learning)?.generation

        XCTAssertFalse(try controller.restoreDefaults(confirmed: false))
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .settings)), settingsBefore)
        XCTAssertTrue(session.applied.isEmpty)

        writer.failureInjector = { stage in
            if stage == .afterCurrentReplacement { throw SettingsIntegrationError.interrupted }
        }
        XCTAssertThrowsError(try controller.restoreDefaults(confirmed: true))
        XCTAssertEqual(controller.savedSettings, changed)
        XCTAssertEqual(store.settings, changed)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .settings)), settingsBefore)
        XCTAssertTrue(session.applied.isEmpty)

        writer.failureInjector = nil
        XCTAssertTrue(try controller.restoreDefaults(confirmed: true))
        XCTAssertEqual(controller.savedSettings, .default)
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(store.generation, 2)
        XCTAssertEqual(session.applied, [.default])
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .userLexicon)), userBefore)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .learning)), learningBefore)
        XCTAssertEqual(try writer.load(.userLexicon)?.generation, userGeneration)
        XCTAssertEqual(try writer.load(.learning)?.generation, learningGeneration)
    }
}

private enum SettingsIntegrationError: Error { case interrupted }

private final class SettingsAppearancePresenter: CandidateAppearanceApplying {
    var applied = [InputSettings]()
    var isVisible = false
    func apply(settings: InputSettings) { applied.append(settings) }
    func update(with page: CandidatePage) {}
    func show() {}
    func hide() {}
    func setAnchorTopLeft(_ point: NSPoint) {}
    func setSelectionHandler(_ handler: @escaping (Int) -> Void) {}
}

private final class SettingsInputClient: InputClientProxy {
    private(set) var clearCount = 0
    func setMarkedText(_ text: String) throws {}
    func commitText(_ text: String) throws {}
    func clearMarkedText() throws { clearCount += 1 }
    func candidateAnchorTopLeft() -> NSPoint? { nil }
}

private final class SettingsIntegrationSession: SettingsSessionControlling {
    var state = CompositionState.idle
    var applied = [InputSettings]()
    var activeSnapshot = SettingsSnapshot(generation: 0, settings: .default)
    var pendingSnapshot: SettingsSnapshot?
    func stage(settingsSnapshot: SettingsSnapshot) {
        if state == .idle {
            activeSnapshot = settingsSnapshot
            applied.append(settingsSnapshot.settings)
        } else if pendingSnapshot == nil
                    || settingsSnapshot.generation >= pendingSnapshot!.generation {
            pendingSnapshot = settingsSnapshot
        }
    }
    func applyPendingSettingsIfIdle() {
        guard state == .idle, let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        activeSnapshot = pendingSnapshot
        applied.append(pendingSnapshot.settings)
    }
}
