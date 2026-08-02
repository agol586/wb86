import AppKit
import XCTest
@testable import MacWubi

final class InputModeTests: XCTestCase {
    func testKeyBindingValidatorReportsFieldLevelConflicts() {
        struct ValidationCase {
            let name: String
            let language: ModeSwitchBinding
            let script: ModeSwitchBinding
            let width: ModeSwitchBinding
            let layout: KeyboardLayoutSelection
            let layoutAvailable: Bool
            let expected: [KeyBindingConflict]
        }

        let cases = [
            ValidationCase(
                name: "legal presets",
                language: .standaloneShift, script: .controlShiftF, width: .shiftSpace,
                layout: .us, layoutAvailable: true,
                expected: []
            ),
            ValidationCase(
                name: "empty custom value",
                language: .custom("  "), script: .controlShiftF, width: .shiftSpace,
                layout: .us, layoutAvailable: true,
                expected: [.init(field: .languageSwitch, reason: .empty)]
            ),
            ValidationCase(
                name: "duplicate exact mapping",
                language: .controlShiftF, script: .controlShiftF, width: .disabled,
                layout: .us, layoutAvailable: true,
                expected: [.init(field: .scriptSwitch,
                                 reason: .duplicate(existing: .languageSwitch))]
            ),
            ValidationCase(
                name: "legacy range overlaps exact mapping",
                language: .legacyControlShiftDigits,
                script: .custom("control-shift-2"), width: .disabled,
                layout: .us, layoutAvailable: true,
                expected: [
                    .init(field: .languageSwitch, reason: .unsupportedLegacy),
                    .init(field: .scriptSwitch,
                          reason: .rangeOverlap(existing: .languageSwitch))
                ]
            ),
            ValidationCase(
                name: "system reserved mapping",
                language: .custom("command-space"), script: .disabled, width: .disabled,
                layout: .us, layoutAvailable: true,
                expected: [.init(field: .languageSwitch, reason: .systemReserved)]
            ),
            ValidationCase(
                name: "unavailable current layout",
                language: .standaloneShift, script: .controlShiftF, width: .disabled,
                layout: .followSystem, layoutAvailable: false,
                expected: [.init(field: .keyboardLayout, reason: .layoutUnavailable)]
            )
        ]

        for item in cases {
            let validator = KeyBindingValidator { selection in
                selection == .us || item.layoutAvailable
            }
            XCTAssertEqual(
                validator.validate(languageSwitch: item.language,
                                   scriptSwitch: item.script,
                                   widthSwitch: item.width,
                                   keyboardLayout: item.layout).conflicts,
                item.expected,
                item.name
            )
        }
    }

    func testStructuredBindingDefaultsAndIndependentPagingGroups() throws {
        let fresh = KeyBindingSettings.default
        XCTAssertEqual(fresh.languageSwitch, .standaloneShift)
        XCTAssertEqual(fresh.scriptSwitch, .controlShiftF)
        XCTAssertEqual(fresh.widthSwitch, .disabled)
        XCTAssertEqual(fresh.pageKeyGroups,
                       [.commaPeriod, .minusEquals, .bracketPair, .tab])
        XCTAssertEqual(fresh.keyboardLayout, .us)

        let compatible = KeyBindingSettings.migrationCompatibilityDefault
        XCTAssertEqual(compatible.languageSwitch, .legacyControlShiftDigits)
        XCTAssertEqual(compatible.pageKeyGroups, [.minusEquals])
        XCTAssertEqual(compatible.keyboardLayout, .followSystem)

        let configured = try KeyBindingSettings(
            languageSwitch: .disabled,
            scriptSwitch: .controlShiftF,
            widthSwitch: .shiftSpace,
            pageKeyGroups: [.arrows, .tab],
            keyboardLayout: .followSystem
        )
        XCTAssertEqual(configured.pageKeyGroups.count, 2)
    }

    func testLanguageSwitchIsSessionLocalAndDirectEnglishDoesNotQuery() {
        var queryCount = 0
        let engine = InputEngine { _, _ in
            queryCount += 1
            throw TestError.unexpectedQuery
        }

        let switched = engine.process(.switchLanguage)
        XCTAssertTrue(switched.consumed)
        XCTAssertEqual(switched.clientAction, .none)
        XCTAssertEqual(engine.mode.language, .directEnglish)
        XCTAssertFalse(engine.process(.letter("a")).consumed)
        XCTAssertEqual(queryCount, 0)

        _ = engine.process(.switchLanguage)
        XCTAssertEqual(engine.mode.language, .chinese)
    }

    func testModeSwitchCancelsCompositionBeforeChangingMode() throws {
        let engine = InputEngine(query: query)
        _ = engine.process(.letter("w"))

        let result = engine.process(.switchPunctuation)

        XCTAssertEqual(result.state, .idle)
        XCTAssertEqual(result.clientAction, .clearMarkedText)
        XCTAssertEqual(result.candidateAction, .hide)
        XCTAssertNil(result.learningDelta)
        XCTAssertEqual(engine.mode.punctuation, .english)
    }

    func testModeFieldsToggleIndependently() {
        let engine = InputEngine(query: query)
        _ = engine.process(.switchWidth)
        XCTAssertEqual(engine.mode.width, .full)
        XCTAssertEqual(engine.mode.script, .simplified)
        XCTAssertEqual(engine.mode.punctuation, .chinese)

        _ = engine.process(.switchScript)
        XCTAssertEqual(engine.mode.script, .traditional)
        XCTAssertEqual(engine.mode.width, .full)
    }

    func testSystemShortcutPassThroughNeverChangesModeOrCommitsComposition() throws {
        let engine = InputEngine(query: query)
        let originalMode = engine.mode
        _ = engine.process(.letter("a"))

        let result = engine.process(.passThrough)

        XCTAssertFalse(result.consumed)
        XCTAssertEqual(result.clientAction, .clearMarkedText)
        XCTAssertEqual(result.candidateAction, .hide)
        XCTAssertEqual(engine.mode, originalMode)
        XCTAssertNil(result.learningDelta)
    }

    func testUnconvertedTextPassesThroughAndConvertedTextIsCommitted() {
        let engine = InputEngine(query: query)
        let letterLikeDigit = engine.process(.text("1"))
        XCTAssertFalse(letterLikeDigit.consumed)

        let comma = engine.process(.text(","))
        XCTAssertTrue(comma.consumed)
        XCTAssertEqual(comma.clientAction, .commitText("，"))
        XCTAssertEqual(comma.state, .idle)
    }

    func testOnlyDocumentedModeShortcutsAreIntercepted() throws {
        let legacy = KeyBindingSettings.migrationCompatibilityDefault
        XCTAssertEqual(InputEventMapper.map(try keyEvent(keyCode: 18, characters: "1",
                                                        flags: [.control, .shift]),
                                              isComposing: false, keyBindings: legacy), .switchLanguage)
        XCTAssertEqual(InputEventMapper.map(try keyEvent(keyCode: 19, characters: "2",
                                                        flags: [.control, .shift]),
                                              isComposing: false, keyBindings: legacy), .switchPunctuation)
        XCTAssertEqual(InputEventMapper.map(try keyEvent(keyCode: 20, characters: "3",
                                                        flags: [.control, .shift]),
                                              isComposing: false, keyBindings: legacy), .switchWidth)
        XCTAssertEqual(InputEventMapper.map(try keyEvent(keyCode: 21, characters: "4",
                                                        flags: [.control, .shift]),
                                              isComposing: false, keyBindings: legacy), .switchScript)
        XCTAssertEqual(InputEventMapper.map(try keyEvent(keyCode: 49, characters: " ",
                                                        flags: [.control]),
                                              isComposing: false), .passThrough)
        XCTAssertEqual(InputEventMapper.map(try keyEvent(keyCode: 0, characters: "a",
                                                        flags: [.command]),
                                              isComposing: true), .passThrough)
    }

    func testIndependentModeBindingsRequireExactModifiersAndNonRepeat() throws {
        let bindings = try KeyBindingSettings(
            languageSwitch: .disabled,
            scriptSwitch: .controlShiftF,
            widthSwitch: .shiftSpace,
            pageKeyGroups: [],
            keyboardLayout: .us
        )
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 3, characters: "f", flags: [.control, .shift]),
            isComposing: false, keyBindings: bindings
        ), .switchScript)
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 49, characters: " ", flags: [.shift]),
            isComposing: true, keyBindings: bindings
        ), .switchWidth)
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 3, characters: "f", flags: [.control, .shift, .option]),
            isComposing: false, keyBindings: bindings
        ), .passThrough)
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 3, characters: "f", flags: [.control, .shift],
                         isARepeat: true),
            isComposing: false, keyBindings: bindings
        ), .passThrough)
    }

    func testConfiguredModeBindingPrecedesSystemShortcutAndCandidatesNeverStealThem() throws {
        let bindings = try KeyBindingSettings(
            languageSwitch: .controlShiftF,
            scriptSwitch: .disabled,
            widthSwitch: .disabled,
            pageKeyGroups: [.commaPeriod],
            keyboardLayout: .us
        )
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 3, characters: "f", flags: [.control, .shift]),
            isComposing: true, keyBindings: bindings
        ), .switchLanguage)
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 18, characters: "1", flags: [.command]),
            isComposing: true, keyBindings: bindings
        ), .passThrough)
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 43, characters: ",", flags: [.control]),
            isComposing: true, keyBindings: bindings
        ), .passThrough)
    }

    func testCandidateControlsAreOrdinaryTextWhenIdle() throws {
        let digit = try keyEvent(keyCode: 18, characters: "1")
        XCTAssertEqual(InputEventMapper.map(digit, isComposing: false), .text("1"))
        XCTAssertEqual(InputEventMapper.map(digit, isComposing: true), .select(1))
    }

    func testConfiguredPageKeysAndDisabledModeShortcuts() throws {
        let comma = try keyEvent(keyCode: 43, characters: ",")
        let period = try keyEvent(keyCode: 47, characters: ".")
        let minus = try keyEvent(keyCode: 27, characters: "-")
        let disabled = try KeyBindingSettings(modeSwitch: .disabled, pageKeys: .commaPeriod)

        XCTAssertEqual(InputEventMapper.map(comma, isComposing: true,
                                            keyBindings: disabled), .pagePrevious)
        XCTAssertEqual(InputEventMapper.map(period, isComposing: true,
                                            keyBindings: disabled), .pageNext)
        XCTAssertEqual(InputEventMapper.map(minus, isComposing: true,
                                            keyBindings: disabled), .text("-"))
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 18, characters: "1", flags: [.control, .shift]),
            isComposing: false,
            keyBindings: disabled
        ), .passThrough)
    }

    func testAllEnabledPageGroupsMapBothDirectionsOnlyDuringComposition() throws {
        let bindings = try KeyBindingSettings(
            languageSwitch: .disabled,
            scriptSwitch: .disabled,
            widthSwitch: .disabled,
            pageKeyGroups: Set(CandidatePageKeyGroup.allCases),
            keyboardLayout: .us
        )
        let cases: [(UInt16, String, NSEvent.ModifierFlags, InputEvent)] = [
            (43, ",", [], .pagePrevious), (47, ".", [], .pageNext),
            (27, "-", [], .pagePrevious), (24, "=", [], .pageNext),
            (33, "[", [], .pagePrevious), (30, "]", [], .pageNext),
            (48, "\t", [.shift], .pagePrevious), (48, "\t", [], .pageNext),
            (126, "", [], .pagePrevious), (125, "", [], .pageNext)
        ]
        for (keyCode, characters, flags, expected) in cases {
            XCTAssertEqual(InputEventMapper.map(
                try keyEvent(keyCode: keyCode, characters: characters, flags: flags),
                isComposing: true, keyBindings: bindings
            ), expected)
        }

        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 43, characters: ","),
            isComposing: false, keyBindings: bindings
        ), .text(","))
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 43, characters: ",", flags: [.shift]),
            isComposing: true, keyBindings: bindings
        ), .passThrough)
    }

    func testPagingBoundariesAndMissingSecondThirdShortcutsRemainUnhandled() throws {
        let engine = InputEngine { code, pageIndex in
            let count = pageIndex == 0 ? 5 : 1
            let candidates = try (1...count).map { ordinal in
                try Candidate(text: "候选\(pageIndex)-\(ordinal)", code: code, source: .base,
                              baseRank: ordinal - 1, learnedScore: 0, ordinal: ordinal)
            }
            return try CandidatePage(items: candidates, pageIndex: pageIndex,
                                     pageSize: 5, totalCount: 6)
        }
        _ = engine.process(.letter("a"))
        let firstPage = engine.state
        XCTAssertFalse(engine.process(.pagePrevious).consumed)
        XCTAssertEqual(engine.state, firstPage)

        XCTAssertTrue(engine.process(.pageNext).consumed)
        let lastPage = engine.state
        XCTAssertFalse(engine.process(.pageNext).consumed)
        XCTAssertEqual(engine.state, lastPage)
        XCTAssertFalse(engine.process(.select(2)).consumed)
        XCTAssertFalse(engine.process(.select(3)).consumed)
        XCTAssertEqual(engine.state, lastPage)
    }

    func testSemicolonAndQuoteShortcutsRequireSettingCompositionAndExactModifiers() throws {
        let bindings = try KeyBindingSettings(
            languageSwitch: .disabled, scriptSwitch: .disabled, widthSwitch: .disabled,
            pageKeyGroups: [], keyboardLayout: .us
        )
        let semicolon = try keyEvent(keyCode: 41, characters: ";")
        let quote = try keyEvent(keyCode: 39, characters: "'")
        XCTAssertEqual(InputEventMapper.map(semicolon, isComposing: true,
                                            keyBindings: bindings,
                                            candidate2And3ShortcutsEnabled: true), .select(2))
        XCTAssertEqual(InputEventMapper.map(quote, isComposing: true,
                                            keyBindings: bindings,
                                            candidate2And3ShortcutsEnabled: true), .select(3))
        XCTAssertEqual(InputEventMapper.map(semicolon, isComposing: false,
                                            keyBindings: bindings,
                                            candidate2And3ShortcutsEnabled: true), .text(";"))
        XCTAssertEqual(InputEventMapper.map(semicolon, isComposing: true,
                                            keyBindings: bindings,
                                            candidate2And3ShortcutsEnabled: false), .text(";"))
        XCTAssertEqual(InputEventMapper.map(
            try keyEvent(keyCode: 41, characters: ";", flags: [.shift]),
            isComposing: true, keyBindings: bindings,
            candidate2And3ShortcutsEnabled: true
        ), .passThrough)
    }

    func testVisibleIndicatorAndInputMenuContainNoInputText() {
        let traditional = InputMode(language: .chinese, punctuation: .english,
                                    width: .full, script: .traditional)
        XCTAssertEqual(InputModeController.label(for: traditional), "五·中·英标·全·繁")
        let menu = InputModeController.shared.menu(mode: traditional) { _ in }
        XCTAssertEqual(menu.items.count, 6)
        XCTAssertEqual(Array(menu.items.prefix(4)).map(\.state), [.on, .off, .on, .on])
        XCTAssertEqual(menu.items.last?.title, "设置…")
        XCTAssertTrue(menu.items.allSatisfy { !$0.title.contains("候选") })
    }

    private func keyEvent(keyCode: UInt16, characters: String,
                          flags: NSEvent.ModifierFlags = [],
                          isARepeat: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    private func query(code: InputCode, pageIndex: Int) throws -> CandidatePage {
        let candidate = try Candidate(text: "候选", code: code, source: .base,
                                      baseRank: 0, learnedScore: 0, ordinal: 1)
        return try CandidatePage(items: [candidate], pageIndex: pageIndex,
                                 pageSize: 5, totalCount: 1)
    }

    private enum TestError: Error { case unexpectedQuery }
}
