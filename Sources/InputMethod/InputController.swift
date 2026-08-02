import AppKit
import InputMethodKit

@objc(InputController)
@MainActor
final class InputController: IMKInputController {
    private var inputSession: InputControllerSession!
    private var candidatePresenter: AccessibleCandidatePresenter!
    private var clientProxy: IMKClientProxy?

    private(set) var compositionState: CompositionState {
        get { inputSession?.state ?? .idle }
        set {
            if newValue == .idle { inputSession?.resetWithoutClient() }
        }
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        candidatePresenter = AccessibleCandidatePresenter()
        inputSession = InputControllerSession(
            engine: InputEngine(
                scriptConverter: Self.makeScriptConverter(),
                query: Self.makeDictionaryQuery()
            ),
            presenter: candidatePresenter,
            learningHandler: PersonalizationCoordinator.shared.record
        )
        PrivacyModeController.shared.register(inputSession)
        SettingsCoordinator.shared?.register(inputSession)
        if let inputClient {
            clientProxy = IMKClientProxy(inputClient)
        }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = proxy(for: sender) else {
            resetSession()
            return false
        }
        let mappedEvent = InputEventMapper.map(
            event,
            isComposing: compositionState.kind == .composing,
            keyBindings: inputSession.settings.keyBindings
        )
        let consumed = inputSession.handle(mappedEvent, client: client)
        SettingsCoordinator.shared?.applyPendingAtIdle()
        InputModeController.shared.activate(mode: inputSession.mode) { [weak self] modeEvent in
            self?.handleModeEvent(modeEvent)
        }
        return consumed
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = proxy(for: sender) {
            inputSession.deactivate(client: client)
        } else {
            resetSession()
        }
    }

    override func commitComposition(_ sender: Any!) {
        // A client-requested end is a privacy-safe cancellation. Calling super here would
        // restore originalString and could insert the raw Wubi code into the document.
        if let client = proxy(for: sender) {
            inputSession.deactivate(client: client)
        } else {
            resetSession()
        }
    }

    override func inputControllerWillClose() {
        if let clientProxy {
            inputSession.deactivate(client: clientProxy)
        } else {
            resetSession()
        }
        super.inputControllerWillClose()
    }

    func resetSession() {
        inputSession?.resetWithoutClient()
        candidatePresenter?.hide()
    }

    private func proxy(for sender: Any?) -> IMKClientProxy? {
        if let sender, let proxy = IMKClientProxy(sender) {
            clientProxy = proxy
        }
        return clientProxy
    }

    private static func makeDictionaryQuery() -> InputEngine.Query {
        return { code, pageIndex in
            try PersonalizationCoordinator.shared.page(for: code, pageIndex: pageIndex)
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
