import AppKit

final class InputModeController: NSObject {
    static let shared = InputModeController()

    private var currentMode = InputMode.default

    private override init() { super.init() }

    func activate(mode: InputMode) {
        precondition(Thread.isMainThread)
        update(mode: mode)
    }

    func menu(mode: InputMode) -> NSMenu {
        activate(mode: mode)
        return makeMenu()
    }

    func update(mode: InputMode) {
        precondition(Thread.isMainThread)
        currentMode = mode
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Mac Wubi 输入模式")
        menu.autoenablesItems = false
        menu.addItem(item(title: "中文输入", event: .switchLanguage,
                          checked: currentMode.language == .chinese))
        menu.addItem(item(title: "中文标点", event: .switchPunctuation,
                          checked: currentMode.punctuation == .chinese))
        menu.addItem(item(title: "全角字符", event: .switchWidth,
                          checked: currentMode.width == .full))
        menu.addItem(item(title: "繁体输出", event: .switchScript,
                          checked: currentMode.script == .traditional))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…",
                                  action: NSSelectorFromString("showSettings:"),
                                  keyEquivalent: ",")
        menu.addItem(settings)
        return menu
    }

    private func item(title: String, event: InputEvent, checked: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title,
                              action: NSSelectorFromString("selectInputMode:"),
                              keyEquivalent: "")
        item.tag = Self.commandTag(for: event)
        item.state = checked ? .on : .off
        item.isEnabled = true
        return item
    }

    static func event(forCommandTag tag: Int) -> InputEvent? {
        switch tag {
        case 1: return .switchLanguage
        case 2: return .switchPunctuation
        case 3: return .switchWidth
        case 4: return .switchScript
        default: return nil
        }
    }

    private static func commandTag(for event: InputEvent) -> Int {
        switch event {
        case .switchLanguage: return 1
        case .switchPunctuation: return 2
        case .switchWidth: return 3
        case .switchScript: return 4
        case .letter, .select, .selectFirst, .pagePrevious, .pageNext, .backspace,
             .cancel, .text, .passThrough:
            preconditionFailure("only mode events belong in the input menu")
        }
    }

    static func label(for mode: InputMode) -> String {
        let language = mode.language == .chinese ? "中" : "英"
        let punctuation = mode.punctuation == .chinese ? "中标" : "英标"
        let width = mode.width == .half ? "半" : "全"
        let script = mode.script == .simplified ? "简" : "繁"
        return "五·\(language)·\(punctuation)·\(width)·\(script)"
    }

}
