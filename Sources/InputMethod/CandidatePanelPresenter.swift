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
    var visualCornerRadius: CGFloat { effectView.layer?.cornerRadius ?? 0 }
    var visualBorderWidth: CGFloat { effectView.layer?.borderWidth ?? 0 }
    var showsPageIndicator: Bool { !pageLabel.isHidden }
    var emphasizedCandidateOrdinals: [Int] {
        candidateButtons.values.compactMap { button in
            (button as? CandidateRowButton)?.isDefaultCandidate == true ? button.tag : nil
        }.sorted()
    }
    var candidateRowsHavePointerFeedback: Bool {
        !candidateButtons.isEmpty && candidateButtons.values.allSatisfy { $0 is CandidateRowButton }
    }
    var usesCandidateTextHierarchy: Bool {
        candidateButtons.values.allSatisfy { $0.attributedTitle.length > 0 }
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
            ofSize: CandidateTypography.candidatePointSize(
                for: appearanceSettings.candidateFontScale
            ),
            weight: .regular
        )

        for (index, candidate) in page.items.enumerated() {
            let row = layoutController.rowPresentation(
                for: candidate,
                showsCodeHint: appearanceSettings.codeHintEnabled,
                maximumWidth: 504,
                font: font
            )
            let button = CandidateRowButton(
                title: row.title,
                target: self,
                action: #selector(selectCandidate(_:))
            )
            button.tag = candidate.ordinal
            button.isDefaultCandidate = index == 0
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
            button.font = font
            button.contentTintColor = .labelColor
            button.attributedTitle = styledTitle(for: candidate, row: row, font: font)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
            candidateButtons[candidate.ordinal] = button
            candidateStack.addArrangedSubview(button)
        }

        let pageNumber = page.pageIndex + 1
        let pageCount = max(1, (page.totalCount + page.pageSize - 1) / page.pageSize)
        pageLabel.stringValue = "\(pageNumber) / \(pageCount)"
        pageLabel.isHidden = page.items.isEmpty || pageCount <= 1
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
        pageLabel.font = .systemFont(
            ofSize: CandidateTypography.pagePointSize(for: settings.candidateFontScale),
            weight: .medium
        )
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
        panel.backgroundColor = .clear
        panel.isOpaque = false
    }

    private func configureContent() {
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor

        candidateStack.orientation = .vertical
        candidateStack.alignment = .leading
        candidateStack.spacing = 4
        candidateStack.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(candidateStack)
        effectView.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            candidateStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            candidateStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            pageLabel.leadingAnchor.constraint(equalTo: candidateStack.leadingAnchor),
            pageLabel.trailingAnchor.constraint(lessThanOrEqualTo: effectView.trailingAnchor, constant: -10),
            pageLabel.topAnchor.constraint(equalTo: candidateStack.bottomAnchor, constant: 4),
            pageLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8)
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
        effectView.layer?.borderWidth = result.usesHighContrastBorder ? 2 : 1
        effectView.layer?.borderColor = result.usesHighContrastBorder
            ? NSColor.labelColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        panel.setFrame(result.frame, display: true, animate: result.animates && panel.isVisible)
    }

    @objc private func selectCandidate(_ sender: NSButton) {
        selectionHandler(sender.tag)
    }

    private func styledTitle(for candidate: Candidate, row: CandidateRowPresentation,
                             font: NSFont) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: row.title,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        let ordinal = "\(candidate.ordinal)"
        title.addAttributes([
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: max(11, font.pointSize - 1), weight: .semibold
            ),
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: NSRange(location: 0, length: ordinal.utf16.count))

        let candidateRange = (row.title as NSString).range(of: candidate.text)
        if candidateRange.location != NSNotFound {
            title.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: font.pointSize, weight: .medium),
                range: candidateRange
            )
        }
        if let hint = row.visibleHint {
            let hintRange = (row.title as NSString).range(of: hint, options: .backwards)
            if hintRange.location != NSNotFound {
                title.addAttributes([
                    .font: NSFont.monospacedSystemFont(
                        ofSize: max(11, font.pointSize - 2), weight: .regular
                    ),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ], range: hintRange)
            }
        }
        return title
    }
}

private final class CandidateRowButton: NSButton {
    var isDefaultCandidate = false { didSet { refreshBackground() } }
    private var isPointerInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        refreshBackground()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        super.mouseDown(with: event)
        refreshBackground()
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        refreshBackground()
    }

    private func refreshBackground() {
        let alpha: CGFloat = isPointerInside ? 0.20 : (isDefaultCandidate ? 0.12 : 0)
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
    }
}

private final class NonActivatingCandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
