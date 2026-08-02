import AppKit
import XCTest
@testable import MacWubi

final class ModeInputIntegrationTests: XCTestCase {
    @MainActor
    func testCandidateApplicationShortcutAndPagingMatrixProducesAtMostOneClientAction() throws {
        var settings = InputSettings.default
        settings.candidate2And3ShortcutsEnabled = true
        settings.autoCommitAtFour = false
        let snapshot = SettingsSnapshot(generation: 1, settings: settings)
        let router = InputControllerEventRouter()
        let client = ModeMatrixClient()
        let presenter = ModeMatrixPresenter()
        let session = InputControllerSession(
            engine: InputEngine { code, pageIndex in
                let count = pageIndex == 0 ? 5 : 1
                let items = try (1...count).map { ordinal in
                    try Candidate(text: "候选\(pageIndex)-\(ordinal)", code: code,
                                  source: .base, baseRank: ordinal - 1,
                                  learnedScore: 0, ordinal: ordinal)
                }
                return try CandidatePage(items: items, pageIndex: pageIndex,
                                         pageSize: 5, totalCount: 6)
            },
            presenter: presenter
        )
        session.stage(settingsSnapshot: snapshot)

        @discardableResult
        func send(_ event: NSEvent) -> (route: InputControllerEventRoute, consumed: Bool) {
            let before = client.actions.count
            let route = router.route(event, settingsSnapshot: session.activeSnapshot,
                                     isComposing: session.state.kind == .composing)
            let consumed = route.coreEvent.map { session.handle($0, client: client) } ?? false
            XCTAssertLessThanOrEqual(client.actions.count - before, 1)
            return (route, route.mustPassThrough ? false : consumed)
        }

        _ = send(try matrixEvent(keyCode: 0, characters: "x", timestamp: 1))
        let selected = send(try matrixEvent(keyCode: 41, characters: "x", timestamp: 2))
        XCTAssertEqual(selected.route.coreEvent, .select(2))
        XCTAssertTrue(selected.consumed)
        XCTAssertEqual(client.committed, ["候选0-2"])

        _ = send(try matrixEvent(keyCode: 0, characters: "x", timestamp: 3))
        let page = send(try matrixEvent(keyCode: 48, characters: "", timestamp: 4))
        XCTAssertEqual(page.route.coreEvent, .pageNext)
        XCTAssertTrue(page.consumed)
        XCTAssertEqual(presenter.page?.pageIndex, 1)

        let boundary = send(try matrixEvent(keyCode: 48, characters: "", timestamp: 5))
        XCTAssertEqual(boundary.route.coreEvent, .pageNext)
        XCTAssertFalse(boundary.consumed)
        XCTAssertEqual(presenter.page?.pageIndex, 1)

        let shortcut = send(try matrixEvent(keyCode: 8, characters: "x",
                                            flags: [.command], timestamp: 6))
        XCTAssertEqual(shortcut.route.coreEvent, .passThrough)
        XCTAssertFalse(shortcut.consumed)
        XCTAssertEqual(client.actions.last, .cleared)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(client.committed, ["候选0-2"])
    }

    func testDocumentedMixedLanguageModeFlowProducesExpectedTranscript() throws {
        let converter = try ScriptConverter(data: bundledConversionData())
        let words = ["w": "你", "q": "好", "t": "测", "s": "试", "y": "中国"]
        let engine = InputEngine(scriptConverter: converter) { code, pageIndex in
            guard pageIndex == 0, let text = words[code.letters] else {
                return try CandidatePage(items: [], pageIndex: pageIndex,
                                         pageSize: 5, totalCount: 0)
            }
            let candidate = try Candidate(text: text, code: code, source: .base,
                                          baseRank: 0, learnedScore: 0, ordinal: 1)
            return try CandidatePage(items: [candidate], pageIndex: 0,
                                     pageSize: 5, totalCount: 1)
        }
        var transcript = ""

        func send(_ event: InputEvent, raw: String? = nil) {
            let result = engine.process(event)
            if case let .commitText(text) = result.clientAction { transcript.append(text) }
            if !result.consumed, let raw { transcript.append(raw) }
        }

        send(.letter("w")); send(.selectFirst)
        send(.letter("q")); send(.selectFirst)
        send(.text(","), raw: ",")
        send(.switchLanguage)
        for character in "macwubi42" {
            let raw = String(character)
            send(InputCode(raw) == nil ? .text(raw) : .letter(raw), raw: raw)
        }
        send(.switchLanguage)
        send(.text("\""), raw: "\"")
        send(.letter("t")); send(.selectFirst)
        send(.letter("s")); send(.selectFirst)
        send(.text("\""), raw: "\"")
        send(.text("?"), raw: "?")
        send(.switchWidth)
        send(.text("1"), raw: "1"); send(.text("2"), raw: "2")
        send(.switchWidth)
        send(.switchScript)
        send(.letter("y")); send(.selectFirst)

        XCTAssertEqual(transcript, "你好，macwubi42“测试”？１２中國")
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.mode, InputMode(language: .chinese, punctuation: .chinese,
                                               width: .half, script: .traditional))
    }

    private func bundledConversionData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "script-conversion", withExtension: "bin")
                ?? Bundle(for: Self.self).url(forResource: "script-conversion", withExtension: "bin")
        )
        return try Data(contentsOf: url)
    }

    private func matrixEvent(keyCode: UInt16, characters: String,
                             flags: NSEvent.ModifierFlags = [],
                             timestamp: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

private final class ModeMatrixClient: InputClientProxy {
    enum Action: Equatable { case marked(String), committed(String), cleared }
    private(set) var actions = [Action]()
    var committed: [String] {
        actions.compactMap { action in
            guard case let .committed(text) = action else { return nil }
            return text
        }
    }
    func setMarkedText(_ text: String) throws { actions.append(.marked(text)) }
    func commitText(_ text: String) throws { actions.append(.committed(text)) }
    func clearMarkedText() throws { actions.append(.cleared) }
    func candidateAnchorTopLeft() -> NSPoint? { nil }
}

private final class ModeMatrixPresenter: CandidatePresenting {
    var isVisible = false
    private(set) var page: CandidatePage?
    func update(with page: CandidatePage) { self.page = page }
    func show() { isVisible = true }
    func hide() { isVisible = false }
    func setAnchorTopLeft(_ point: NSPoint) {}
    func setSelectionHandler(_ handler: @escaping (Int) -> Void) {}
}
