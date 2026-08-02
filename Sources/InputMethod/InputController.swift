import AppKit
import InputMethodKit

struct InputControllerEventRoute: Equatable {
    let coreEvent: InputEvent?
    let mustPassThrough: Bool
}

final class InputControllerEventRouter {
    private let shiftRecognizer: StandaloneShiftRecognizer
    private let layoutTranslator: KeyboardLayoutTranslator

    init(shiftRecognizer: StandaloneShiftRecognizer = StandaloneShiftRecognizer(),
         layoutTranslator: KeyboardLayoutTranslator = KeyboardLayoutTranslator()) {
        self.shiftRecognizer = shiftRecognizer
        self.layoutTranslator = layoutTranslator
    }

    static func extendingRecognizedEvents(_ mask: Int) -> Int {
        mask | Int(NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    func route(_ event: NSEvent, settingsSnapshot: SettingsSnapshot,
               isComposing: Bool) -> InputControllerEventRoute {
        if event.type == .flagsChanged {
            let triggered = shiftRecognizer.handle(
                event,
                settingsGeneration: settingsSnapshot.generation
            )
            return InputControllerEventRoute(
                coreEvent: triggered
                    ? standaloneShiftEvent(settingsSnapshot.settings.keyBindings) : nil,
                mustPassThrough: true
            )
        }
        guard event.type == .keyDown else {
            return InputControllerEventRoute(coreEvent: nil, mustPassThrough: true)
        }
        shiftRecognizer.disqualifyForNonModifierKey()
        let settings = settingsSnapshot.settings
        let translated = layoutTranslator.character(
            for: event,
            layout: settings.keyBindings.keyboardLayout
        )
        return InputControllerEventRoute(
            coreEvent: InputEventMapper.map(
                event,
                translatedCharacter: translated,
                isComposing: isComposing,
                keyBindings: settings.keyBindings,
                candidate2And3ShortcutsEnabled: settings.candidate2And3ShortcutsEnabled
            ),
            mustPassThrough: false
        )
    }

    func reset() { shiftRecognizer.reset() }

    private func standaloneShiftEvent(_ bindings: KeyBindingSettings) -> InputEvent? {
        if bindings.languageSwitch == .standaloneShift { return .switchLanguage }
        if bindings.scriptSwitch == .standaloneShift { return .switchScript }
        if bindings.widthSwitch == .standaloneShift { return .switchWidth }
        return nil
    }
}

@objc(InputController)
@MainActor
final class InputController: IMKInputController {
    private var inputSession: InputControllerSession!
    private var candidatePresenter: AccessibleCandidatePresenter!
    private var clientProxy: IMKClientProxy?
    private let eventRouter = InputControllerEventRouter()

    private(set) var compositionState: CompositionState {
        get { inputSession?.state ?? .idle }
        set {
            if newValue == .idle { inputSession?.resetWithoutClient() }
        }
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        candidatePresenter = AccessibleCandidatePresenter()
        let scriptConverter = Self.makeScriptConverter()
        inputSession = InputControllerSession(
            engine: InputEngine(
                sequencePolicyQuery: Self.makeDictionaryQuery(
                    scriptConverter: scriptConverter
                )
            ),
            presenter: candidatePresenter,
            policyLearningHandler: PersonalizationCoordinator.shared.record
        )
        if let inputClient {
            clientProxy = IMKClientProxy(inputClient)
        }
        PrivacyModeController.shared.register(inputSession)
        SettingsCoordinator.shared?.register(inputSession)
    }

    override func activateServer(_ sender: Any!) {
        guard proxy(for: sender) != nil else {
            resetSession()
            return
        }
        eventRouter.reset()
        inputSession.reactivate()
        SettingsCoordinator.shared?.applyPendingAtIdle()
        InputModeController.shared.activate(mode: inputSession.mode) { [weak self] modeEvent in
            self?.handleModeEvent(modeEvent)
        }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = proxy(for: sender) else {
            resetSession()
            return false
        }
        let route = eventRouter.route(
            event,
            settingsSnapshot: inputSession.activeSnapshot,
            isComposing: compositionState.kind == .composing
        )
        guard let mappedEvent = route.coreEvent else { return false }
        let consumed = inputSession.handle(mappedEvent, client: client)
        SettingsCoordinator.shared?.applyPendingAtIdle()
        InputModeController.shared.activate(mode: inputSession.mode) { [weak self] modeEvent in
            self?.handleModeEvent(modeEvent)
        }
        return route.mustPassThrough ? false : consumed
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        InputControllerEventRouter.extendingRecognizedEvents(super.recognizedEvents(sender))
    }

    override func deactivateServer(_ sender: Any!) {
        finishSession(sender: sender)
    }

    override func commitComposition(_ sender: Any!) {
        // A client-requested end is a privacy-safe cancellation. Calling super here would
        // restore originalString and could insert the raw Wubi code into the document.
        finishSession(sender: sender)
    }

    override func inputControllerWillClose() {
        finishSession(sender: nil)
        super.inputControllerWillClose()
    }

    func resetSession() {
        eventRouter.reset()
        inputSession?.resetWithoutClient()
        candidatePresenter?.hide()
        clientProxy = nil
        SettingsCoordinator.shared?.applyPendingAtIdle()
    }

    private func proxy(for sender: Any?) -> IMKClientProxy? {
        if let sender {
            guard let proxy = IMKClientProxy(sender) else { return nil }
            clientProxy = proxy
            return proxy
        }
        return clientProxy
    }

    private func finishSession(sender: Any?) {
        eventRouter.reset()
        if let client = proxy(for: sender) {
            inputSession.deactivate(client: client)
        } else {
            inputSession.resetWithoutClient()
            candidatePresenter.hide()
        }
        clientProxy = nil
        SettingsCoordinator.shared?.applyPendingAtIdle()
    }

    private static func makeDictionaryQuery(scriptConverter: ScriptConverter?)
        -> InputEngine.SequencePolicyQuery {
        return { sequence, pageIndex, policy, mode, mixedPinyinEnabled in
            try PersonalizationCoordinator.shared.page(
                for: sequence,
                pageIndex: pageIndex,
                policy: policy,
                mode: mode,
                mixedPinyinEnabled: mixedPinyinEnabled,
                scriptConverter: scriptConverter
            )
        }
    }

    private static func makeScriptConverter() -> ScriptConverter? {
        guard let url = Bundle.main.url(forResource: "script-conversion", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return try? ScriptConverter(data: data)
    }

    override func menu() -> NSMenu! {
        InputModeController.shared.menu(mode: inputSession.mode) { [weak self] modeEvent in
            self?.handleModeEvent(modeEvent)
        }
    }

    private func handleModeEvent(_ event: InputEvent) {
        guard let clientProxy else { return }
        _ = inputSession.handle(event, client: clientProxy)
        InputModeController.shared.update(mode: inputSession.mode)
    }
}

private final class IMKClientProxy: InputClientProxy {
    private let input: any IMKTextInput

    init?(_ client: Any) {
        guard let input = client as? any IMKTextInput else { return nil }
        self.input = input
    }

    func setMarkedText(_ text: String) throws {
        input.setMarkedText(
            text,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func commitText(_ text: String) throws {
        input.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func clearMarkedText() throws {
        input.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func candidateAnchorTopLeft() -> NSPoint? {
        var lineRect = NSRect.zero
        _ = input.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        guard !lineRect.isEmpty else { return nil }
        return NSPoint(x: lineRect.minX, y: lineRect.minY)
    }
}
