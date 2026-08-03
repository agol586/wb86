import AppKit
import InputMethodKit

struct InputControllerEventRoute: Equatable {
    let coreEvent: InputEvent?
    let mustPassThrough: Bool
}

final class InputControllerEventRouter {
    private let modifierRecognizer: StandaloneModifierRecognizer
    private let layoutTranslator: KeyboardLayoutTranslator

    init(modifierRecognizer: StandaloneModifierRecognizer = StandaloneModifierRecognizer(),
         layoutTranslator: KeyboardLayoutTranslator = KeyboardLayoutTranslator()) {
        self.modifierRecognizer = modifierRecognizer
        self.layoutTranslator = layoutTranslator
    }

    static let recognizedEventMask = Int(
        NSEvent.EventTypeMask.keyDown.rawValue
            | NSEvent.EventTypeMask.flagsChanged.rawValue
    )

    func route(_ event: NSEvent, settingsSnapshot: SettingsSnapshot,
               isComposing: Bool) -> InputControllerEventRoute {
        if event.type == .flagsChanged {
            let triggered = modifierRecognizer.handle(
                event,
                binding: settingsSnapshot.settings.keyBindings.languageSwitch,
                settingsGeneration: settingsSnapshot.generation
            )
            return InputControllerEventRoute(
                coreEvent: triggered ? .switchLanguage : nil,
                mustPassThrough: true
            )
        }
        guard event.type == .keyDown else {
            return InputControllerEventRoute(coreEvent: nil, mustPassThrough: true)
        }
        modifierRecognizer.disqualifyForNonModifierKey()
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

    func reset() { modifierRecognizer.reset() }

    func suspend() { modifierRecognizer.suspend() }
}

@MainActor
final class InputControllerEventProcessor {
    private let router: InputControllerEventRouter

    init(router: InputControllerEventRouter = InputControllerEventRouter()) {
        self.router = router
    }

    /// Observe the event before resolving its text client. Some IMK clients deliver a
    /// flagsChanged edge with a temporarily nil or non-IMKTextInput sender.
    func handle(_ event: NSEvent, session: InputControllerSession,
                settingsSnapshot: SettingsSnapshot,
                resolveClient: () -> InputClientProxy?) -> Bool {
        let route = router.route(
            event,
            settingsSnapshot: settingsSnapshot,
            isComposing: session.state.kind == .composing
        )
        let client = resolveClient()
        guard let mappedEvent = route.coreEvent else { return false }

        let consumed: Bool
        if let client {
            consumed = session.handle(mappedEvent, client: client)
        } else if session.state == .idle {
            consumed = session.handleMenuModeEvent(mappedEvent)
        } else {
            // The owning client is required to clear marked text. Fail closed locally:
            // never commit raw input or apply a mode change to an ambiguous session.
            session.resetWithoutClient()
            return false
        }
        return route.mustPassThrough ? false : consumed
    }

    func reset() { router.reset() }

    func suspend() { router.suspend() }
}

@objc(InputController)
@MainActor
final class InputController: IMKInputController {
    private var inputSession: InputControllerSession!
    private var candidatePresenter: CandidatePanelPresenter!
    private var clientProxy: IMKClientProxy?
    private let eventProcessor = InputControllerEventProcessor()

    private(set) var compositionState: CompositionState {
        get { inputSession?.state ?? .idle }
        set {
            if newValue == .idle { inputSession?.resetWithoutClient() }
        }
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        candidatePresenter = CandidatePanelPresenter()
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
        eventProcessor.suspend()
        guard proxy(for: sender) != nil else {
            inputSession.resetWithoutClient()
            candidatePresenter.hide()
            clientProxy = nil
            SettingsCoordinator.shared?.applyPendingAtIdle()
            return
        }
        inputSession.reactivate()
        SettingsCoordinator.shared?.applyPendingAtIdle()
        InputModeController.shared.activate(mode: inputSession.mode)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            resetSession()
            return false
        }
        let consumed = eventProcessor.handle(
            event,
            session: inputSession,
            settingsSnapshot: inputSession.activeSnapshot,
            resolveClient: { [weak self] in self?.proxy(for: sender) }
        )
        SettingsCoordinator.shared?.applyPendingAtIdle()
        InputModeController.shared.activate(mode: inputSession.mode)
        return consumed
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        InputControllerEventRouter.recognizedEventMask
    }

    override func deactivateServer(_ sender: Any!) {
        finishSession(sender: sender, closingController: false)
    }

    override func commitComposition(_ sender: Any!) {
        // A client-requested end is a privacy-safe cancellation. Calling super here would
        // restore originalString and could insert the raw Wubi code into the document.
        finishSession(sender: sender, closingController: false)
    }

    override func inputControllerWillClose() {
        finishSession(sender: nil, closingController: true)
        super.inputControllerWillClose()
    }

    func resetSession() {
        eventProcessor.reset()
        inputSession?.resetWithoutClient()
        candidatePresenter?.hide()
        clientProxy = nil
        SettingsCoordinator.shared?.applyPendingAtIdle()
    }

    private func proxy(for sender: Any?) -> IMKClientProxy? {
        if let sender, let proxy = IMKClientProxy(sender) {
            clientProxy = proxy
            return proxy
        }
        return clientProxy
    }

    private func finishSession(sender: Any?, closingController: Bool) {
        if closingController {
            eventProcessor.reset()
        } else {
            eventProcessor.suspend()
        }
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
        InputModeController.shared.menu(mode: inputSession.mode)
    }

    override func doCommand(by aSelector: Selector!,
                            command infoDictionary: [AnyHashable: Any]!) {
        switch aSelector.map(NSStringFromSelector) {
        case "selectInputMode:":
            selectInputMode((infoDictionary ?? [:]) as NSDictionary)
        case "showSettings:":
            showSettings((infoDictionary ?? [:]) as NSDictionary)
        default:
            super.doCommand(by: aSelector, command: infoDictionary)
        }
    }

    /// InputMethodKit calls doCommand(by:command:) for system input-menu items and the
    /// superclass dispatches the selector to this controller with an NSDictionary sender.
    @objc func selectInputMode(_ command: NSDictionary) {
        guard let item = command[kIMKCommandMenuItemName] as? NSMenuItem,
              let event = InputModeController.event(forCommandTag: item.tag) else { return }
        handleModeEvent(event)
    }

    @objc func showSettings(_ command: NSDictionary) {
        // InputMethodKit invokes commands while the system input menu is still tracking.
        // Defer presentation until that menu has closed or AppKit may discard the order-front.
        DispatchQueue.main.async {
            SettingsWindowController.shared.show()
        }
    }

    private func handleModeEvent(_ event: InputEvent) {
        if let clientProxy {
            _ = inputSession.handle(event, client: clientProxy)
        } else {
            _ = inputSession.handleMenuModeEvent(event)
        }
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
