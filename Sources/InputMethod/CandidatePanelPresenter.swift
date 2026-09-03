import AppKit

struct CandidateVisualPreferences: Equatable, Sendable {
    let reduceMotion: Bool
    let increaseContrast: Bool
    let reduceTransparency: Bool

    static var system: CandidateVisualPreferences {
        let workspace = NSWorkspace.shared
        return CandidateVisualPreferences(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency
        )
    }
}

final class CandidatePanelPresenter: NSObject, CandidateAppearanceApplying {
    typealias SelectionHandler = (Int) -> Void

    private let panel: NonActivatingCandidatePanel
    private let effectView: NSVisualEffectView
    private let candidateStack: NSStackView
    private let pageSeparator: NSBox
    private let pageLabel: NSTextField
    private var candidateBottomConstraint: NSLayoutConstraint?
    private var pageBottomConstraint: NSLayoutConstraint?
    private var verticalPageConstraints = [NSLayoutConstraint]()
    private var horizontalPageConstraints = [NSLayoutConstraint]()
    private var pageWidthConstraint: NSLayoutConstraint?
    private var selectionHandler: SelectionHandler
    private var anchorTopLeft: NSPoint?
    private var candidateButtons = [Int: NSButton]()
    private var appearanceSettings = InputSettings.migrationCompatibilityDefault
    private var currentPage: CandidatePage?
    private let layoutController = CandidateLayoutController()
    private let visualPreferencesProvider: () -> CandidateVisualPreferences
    private var solidVisualBackground = false

    var displayedPanelSize: NSSize { panel.frame.size }
    var pageIndicatorFrame: NSRect { pageLabel.frame }
    var candidateContentFrame: NSRect { candidateStack.frame }
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
    var displayedPageIndicator: String? { pageLabel.isHidden ? nil : pageLabel.stringValue }
    var pageIndicatorAlignment: NSTextAlignment { pageLabel.alignment }
    var usesSeparatedPageFooter: Bool { !pageSeparator.isHidden && !pageLabel.isHidden }
    var candidateSpacing: CGFloat { candidateStack.spacing }
    var candidateRowsFillAvailableWidth: Bool {
        candidateStack.orientation == .vertical && !candidateButtons.isEmpty &&
            candidateButtons.values.allSatisfy {
                ($0 as? CandidateRowButton)?.fillsAvailableWidth == true
            }
    }
    var emphasizedCandidateOrdinals: [Int] {
        candidateButtons.values.compactMap { button in
            (button as? CandidateRowButton)?.isDefaultCandidate == true ? button.tag : nil
        }.sorted()
    }
    var defaultCandidateIndicatorOrdinals: [Int] {
        candidateButtons.values.compactMap { button in
            (button as? CandidateRowButton)?.showsDefaultIndicator == true ? button.tag : nil
        }.sorted()
    }
    var candidateRowsHavePointerFeedback: Bool {
        !candidateButtons.isEmpty && candidateButtons.values.allSatisfy { $0 is CandidateRowButton }
    }
    var usesCandidateTextHierarchy: Bool {
        candidateButtons.values.allSatisfy { $0.attributedTitle.length > 0 }
    }
    var usesSolidVisualBackground: Bool { solidVisualBackground }
    var usesTranslucentPopoverMaterial: Bool {
        effectView.material == .popover
            && effectView.blendingMode == .behindWindow
            && effectView.state == .active
            && !solidVisualBackground
    }

    init(visualPreferencesProvider: @escaping () -> CandidateVisualPreferences = {
        .system
    }, selectionHandler: @escaping SelectionHandler = { _ in }) {
        self.selectionHandler = selectionHandler
        self.visualPreferencesProvider = visualPreferencesProvider
        panel = NonActivatingCandidatePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        effectView = NSVisualEffectView()
        candidateStack = NSStackView()
        pageSeparator = NSBox()
        pageLabel = NSTextField(labelWithString: "")
        super.init()
        configurePanel()
        configureContent()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
            candidateStack.addArrangedSubview(button)
            if candidateStack.orientation == .vertical {
                button.fillsAvailableWidth = true
                button.widthAnchor.constraint(equalTo: candidateStack.widthAnchor).isActive = true
            }
            candidateButtons[candidate.ordinal] = button
        }

        let pageNumber = page.pageIndex + 1
        let pageCount = max(1, (page.totalCount + page.pageSize - 1) / page.pageSize)
        pageLabel.stringValue = usesHorizontalLayout
            ? "\(pageNumber)/\(pageCount)"
            : "第 \(pageNumber) / \(pageCount) 页"
        configurePagination(hasCandidates: !page.items.isEmpty, pageCount: pageCount)
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
        candidateStack.alignment = settings.candidateLayout == .vertical ? .leading : .centerY
        candidateStack.spacing = settings.candidateLayout == .vertical ? 2 : 8
        pageLabel.font = .monospacedDigitSystemFont(
            ofSize: CandidateTypography.pagePointSize(for: settings.candidateFontScale),
            weight: .medium
        )
        if let currentPage {
            update(with: currentPage)
            return
        }
        resizeToFit()
    }

    func refreshVisualPreferences() {
        refreshVisualStyle(using: visualPreferencesProvider())
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
        candidateStack.spacing = 2
        candidateStack.translatesAutoresizingMaskIntoConstraints = false

        pageSeparator.boxType = .separator
        pageSeparator.translatesAutoresizingMaskIntoConstraints = false
        pageSeparator.isHidden = true

        pageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .right
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.isHidden = true
        pageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        effectView.addSubview(candidateStack)
        effectView.addSubview(pageSeparator)
        effectView.addSubview(pageLabel)
        candidateBottomConstraint = candidateStack.bottomAnchor.constraint(
            equalTo: effectView.bottomAnchor, constant: -8
        )
        pageBottomConstraint = pageLabel.bottomAnchor.constraint(
            equalTo: effectView.bottomAnchor, constant: -8
        )
        verticalPageConstraints = [
            candidateStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            pageLabel.leadingAnchor.constraint(equalTo: candidateStack.leadingAnchor),
            pageLabel.topAnchor.constraint(equalTo: pageSeparator.bottomAnchor, constant: 4)
        ]
        let pageWidth = pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        pageWidthConstraint = pageWidth
        horizontalPageConstraints = [
            pageLabel.leadingAnchor.constraint(equalTo: candidateStack.trailingAnchor, constant: 12),
            pageLabel.centerYAnchor.constraint(equalTo: candidateStack.centerYAnchor),
            pageWidth
        ]
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            candidateStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            pageSeparator.leadingAnchor.constraint(equalTo: candidateStack.leadingAnchor),
            pageSeparator.trailingAnchor.constraint(equalTo: candidateStack.trailingAnchor),
            pageSeparator.topAnchor.constraint(equalTo: candidateStack.bottomAnchor, constant: 6),
            pageLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10)
        ])
        NSLayoutConstraint.activate(verticalPageConstraints)
        candidateBottomConstraint?.isActive = true
        panel.contentView = effectView
        refreshVisualStyle(using: visualPreferencesProvider())
    }

    private func configurePagination(hasCandidates: Bool, pageCount: Int) {
        NSLayoutConstraint.deactivate(verticalPageConstraints + horizontalPageConstraints)
        candidateBottomConstraint?.isActive = false
        pageBottomConstraint?.isActive = false
        let showsFooter = !usesHorizontalLayout && hasCandidates && pageCount > 1
        pageSeparator.isHidden = !showsFooter
        pageLabel.isHidden = !hasCandidates || (!usesHorizontalLayout && !showsFooter)
        if usesHorizontalLayout {
            // Reserve two digits on each side for the bounded candidate result set.
            let font = pageLabel.font ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            pageWidthConstraint?.constant = ceil(("99/99" as NSString).size(withAttributes: [.font: font]).width) + 4
            NSLayoutConstraint.activate(horizontalPageConstraints)
        } else {
            NSLayoutConstraint.activate(verticalPageConstraints)
        }
        candidateBottomConstraint?.isActive = !showsFooter
        pageBottomConstraint?.isActive = showsFooter
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
        let visualPreferences = visualPreferencesProvider()
        refreshVisualStyle(using: visualPreferences)
        let result = layoutController.layout(
            contentSize: panel.frame.size,
            anchorTopLeft: anchorTopLeft,
            environment: CandidateLayoutEnvironment(
                visibleFrames: NSScreen.screens.map(\.visibleFrame),
                reduceMotion: visualPreferences.reduceMotion,
                increaseContrast: visualPreferences.increaseContrast,
                backingScale: targetScreen?.backingScaleFactor ?? 1
            )
        )
        panel.setFrame(result.frame, display: true, animate: result.animates && panel.isVisible)
    }

    private func refreshVisualStyle(using preferences: CandidateVisualPreferences) {
        solidVisualBackground = preferences.reduceTransparency || preferences.increaseContrast
        if solidVisualBackground {
            effectView.material = .windowBackground
            effectView.blendingMode = .withinWindow
            effectView.state = .inactive
            effectView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        effectView.layer?.borderWidth = preferences.increaseContrast ? 2 : 1
        effectView.layer?.borderColor = preferences.increaseContrast
            ? NSColor.labelColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        precondition(Thread.isMainThread)
        if anchorTopLeft == nil {
            refreshVisualPreferences()
        } else {
            positionAtAnchorIfAvailable()
        }
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
    var fillsAvailableWidth = false
    var showsDefaultIndicator: Bool { isDefaultCandidate && !defaultIndicator.isHidden }
    private var isPointerInside = false
    private let defaultIndicator = CALayer()

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

    override func layout() {
        super.layout()
        defaultIndicator.frame = CGRect(x: 1, y: 5, width: 3,
                                        height: max(0, bounds.height - 10))
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
        defaultIndicator.backgroundColor = NSColor.controlAccentColor.cgColor
        defaultIndicator.cornerRadius = 1.5
        layer?.addSublayer(defaultIndicator)
        refreshBackground()
    }

    private func refreshBackground() {
        defaultIndicator.isHidden = !isDefaultCandidate
        let alpha: CGFloat = isPointerInside ? 0.22 : (isDefaultCandidate ? 0.14 : 0)
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
    }
}

private final class NonActivatingCandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
