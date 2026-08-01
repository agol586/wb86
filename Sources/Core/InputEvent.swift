enum InputEvent: Hashable, Sendable {
    case letter(String)
    case select(Int)
    case selectFirst
    case pagePrevious
    case pageNext
    case backspace
    case cancel
    case switchLanguage
    case switchPunctuation
    case switchWidth
    case switchScript
    case text(String)
    case passThrough
}
