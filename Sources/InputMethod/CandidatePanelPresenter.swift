import AppKit

final class CandidatePanelPresenter: NSObject, CandidateAppearanceApplying {
    typealias SelectionHandler = (Int) -> Void

    private let panel: NonActivatingCandidatePanel
    private let effectView: NSVisualEffectView
    private let candidateStack: NSStackView
    private let pageLabel: NSTextField
    private var selectionHandler: SelectionHandler
    private var anchorTopLeft: NSPoint?
    private var candidateButtons = [Int: NSButton]()
    private var appearanceSettings = InputSettings.migrationCompatibilityDefault
    private var currentPage: CandidatePage?
    private let layoutController = CandidateLayoutController()

    var isVisible: Bool { panel.isVisible }
    var canTakeKeyboardFocus: Bool { panel.canBecomeKey || panel.canBecomeMain }
    var usesHorizontalLayout: Bool { candidateStack.orientation == .horizontal }
    var displayedCandidateTitles: [String] {
        candidateButtons.values.sorted { $0.tag < $1.tag }.map(\.title)
    }
    var displayedCandidateFontSizes: [CGFloat] {
        candidateButtons.values.sorted { $0.tag < $1.tag }.compactMap { $0.font?.pointSize }
    }

    init(selectionHandler: @escaping SelectionHandler = { _ in }) {
        self.selectionHandler = selectionHandler
        panel = NonActivatingCandidatePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        effectView = NSVisualEffectView()
        candidateStack = NSStackView()
        pageLabel = NSTextField(labelWithString: "")
        super.init()
        configurePanel()
        configureContent()
    }

    func update(with page: CandidatePage) {
        precondition(Thread.isMainThread)
        currentPage = page
        candidateStack.arrangedSubviews.forEach { view in
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        candidateButtons.removeAll()

        let font = NSFont.systemFont(
            ofSize: NSFont.systemFontSize * appearanceSettings.candidateFontScale
        )

        for candidate in page.items {
            let row = layoutController.rowPresentation(
                for: candidate,
                showsCodeHint: appearanceSettings.codeHintEnabled,
                maximumWidth: 504,
                font: font
            )
            let button = NSButton(
                title: row.title,
                target: self,
                action: #selector(selectCandidate(_:))
            )
            button.tag = candidate.ordinal
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
            button.font = font
            candidateButtons[candidate.ordinal] = button
            candidateStack.addArrangedSubview(button)
        }

        let pageNumber = page.pageIndex + 1
        let pageCount = max(1, (page.totalCount + page.pageSize - 1) / page.pageSize)
        pageLabel.stringValue = "第 \(pageNumber) 页，共 \(pageCount) 页"
        pageLabel.isHidden = page.items.isEmpty
        resizeToFit()

        if page.items.isEmpty { hide() }
    }

    func show() {
        precondition(Thread.isMainThread)
        guard !candidateStack.arrangedSubviews.isEmpty else { return }
        positionAtAnchorIfAvailable()
        panel.orderFrontRegardless()
    }

    func hide() {
        precondition(Thread.isMainThread)
        panel.orderOut(nil)
    }

    func setAnchorTopLeft(_ point: NSPoint) {
        precondition(Thread.isMainThread)
        anchorTopLeft = point
        positionAtAnchorIfAvailable()
    }

    func setSelectionHandler(_ handler: @escaping SelectionHandler) {
        precondition(Thread.isMainThread)
        selectionHandler = handler
    }

    @discardableResult
    func performMouseSelection(ordinal: Int) -> Bool {
        guard let button = candidateButtons[ordinal], button.isEnabled else { return false }
        button.performClick(nil)
        return true
    }

    func apply(settings: InputSettings) {
        appearanceSettings = settings
        candidateStack.orientation = settings.candidateLayout == .vertical ? .vertical : .horizontal
        pageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize * settings.candidateFontScale)
        if let currentPage {
            update(with: currentPage)
            return
        }
        resizeToFit()
    }

    private func configurePanel() {
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    }

    private func configureContent() {
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        candidateStack.orientation = .vertical
        candidateStack.alignment = .leading
        candidateStack.spacing = 3
        candidateStack.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(candidateStack)
        effectView.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            candidateStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            candidateStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 6),
            pageLabel.leadingAnchor.constraint(equalTo: candidateStack.leadingAnchor),
            pageLabel.trailingAnchor.constraint(lessThanOrEqualTo: effectView.trailingAnchor, constant: -8),
            pageLabel.topAnchor.constraint(equalTo: candidateStack.bottomAnchor, constant: 4),
            pageLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -6)
        ])
        panel.contentView = effectView
    }

    private func resizeToFit() {
        effectView.layoutSubtreeIfNeeded()
        let fittingSize = effectView.fittingSize
        panel.setContentSize(NSSize(
            width: max(140, min(fittingSize.width, 520)),
            height: max(36, fittingSize.height)
        ))
        positionAtAnchorIfAvailable()
    }

    private func positionAtAnchorIfAvailable() {
        guard let anchorTopLeft else { return }
        let targetScreen = NSScreen.screens.first { $0.frame.contains(anchorTopLeft) } ?? NSScreen.main
        let result = layoutController.layout(
            contentSize: panel.frame.size,
            anchorTopLeft: anchorTopLeft,
            environment: CandidateLayoutEnvironment(
                visibleFrames: NSScreen.screens.map(\.visibleFrame),
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                backingScale: targetScreen?.backingScaleFactor ?? 1
            )
        )
        effectView.wantsLayer = result.usesHighContrastBorder
        effectView.layer?.borderWidth = result.usesHighContrastBorder ? 2 : 0
        effectView.layer?.borderColor = result.usesHighContrastBorder ? NSColor.labelColor.cgColor : nil
        panel.setFrame(result.frame, display: true, animate: result.animates && panel.isVisible)
    }

    @objc private func selectCandidate(_ sender: NSButton) {
        selectionHandler(sender.tag)
    }
}

private final class NonActivatingCandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
