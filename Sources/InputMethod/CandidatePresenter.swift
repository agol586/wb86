import AppKit

protocol CandidatePresenting: AnyObject {
    var isVisible: Bool { get }
    func update(with page: CandidatePage)
    func show()
    func hide()
    func setAnchorRect(_ rect: NSRect)
    func setSelectionHandler(_ handler: @escaping (Int) -> Void)
}

final class NullCandidatePresenter: CandidatePresenting {
    private(set) var isVisible = false

    func update(with page: CandidatePage) {}

    func show() {
        isVisible = true
    }

    func hide() {
        isVisible = false
    }

    func setAnchorRect(_ rect: NSRect) {}
    func setSelectionHandler(_ handler: @escaping (Int) -> Void) {}
}
