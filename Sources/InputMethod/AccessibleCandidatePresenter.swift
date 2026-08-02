import AppKit

final class AccessibleCandidatePresenter: NSObject, CandidateAppearanceApplying {
    typealias SelectionHandler = (Int) -> Void

    private let panel: NonActivatingCandidatePanel
    private let effectView: NSVisualEffectView
    private let candidateStack: NSStackView
    private let pageLabel: NSTextField
    private var selectionHandler: SelectionHandler
    private var anchorTopLeft: NSPoint?
    private var candidateButtons = [Int: NSButton]()
    private var lastAnnouncedSnapshot: CandidateAccessibilitySnapshot?
    private var appearanceSettings = InputSettings.migrationCompatibilityDefault
    private var currentPage: CandidatePage?
    private(set) var accessibilitySnapshot: CandidateAccessibilitySnapshot?
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
    var accessibilityTopLevelCandidateOrdinals: [Int] {
        (panel.accessibilityChildren() ?? [])
            .compactMap { ($0 as? NSButton)?.tag }
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
        accessibilitySnapshot = AccessibilityAdapter.snapshot(
            page: page,
            showsCodeHints: appearanceSettings.codeHintEnabled
        )

        let font = NSFont.systemFont(
            ofSize: NSFont.systemFontSize * appearanceSettings.candidateFontScale
        )

        for (index, candidate) in page.items.enumerated() {
            let row = layoutController.rowPresentation(
                for: candidate,
                showsCodeHint: appearanceSettings.codeHintEnabled,
                maximumWidth: 504,
                font: font
            )
            let button = AccessibilityCandidateButton(
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
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel("候选 \(candidate.ordinal)")
            button.setAccessibilityValue(row.accessibilityValue)
            button.setAccessibilitySelected(index == 0)
            var help = index == 0
                ? "当前选中，按下以提交第 \(candidate.ordinal) 个候选"
                : "按下以提交第 \(candidate.ordinal) 个候选"
            if let hint = row.accessibilityHint { help += "，五笔编码 \(hint)" }
            button.setAccessibilityHelp(help)
            button.setAccessibilityParent(panel)
            candidateButtons[candidate.ordinal] = button
            candidateStack.addArrangedSubview(button)
        }

        let pageNumber = page.pageIndex + 1
        let pageCount = max(1, (page.totalCount + page.pageSize - 1) / page.pageSize)
        pageLabel.stringValue = "第 \(pageNumber) 页，共 \(pageCount) 页"
        pageLabel.setAccessibilityLabel("候选页码")
        pageLabel.setAccessibilityValue(accessibilitySnapshot?.pageValue
                                        ?? "第 \(pageNumber) 页，共 \(pageCount) 页")
        pageLabel.setAccessibilityParent(panel)
        pageLabel.isHidden = page.items.isEmpty

        let orderedButtons = candidateButtons.values.sorted { $0.tag < $1.tag }
        panel.setAccessibilityChildren(orderedButtons + [pageLabel])
        resizeToFit()

        if panel.isVisible { publishAccessibilityLayout(isNewPresentation: false) }

        if page.items.isEmpty {
            hide()
        }
    }

    func show() {
        precondition(Thread.isMainThread)
        guard !candidateStack.arrangedSubviews.isEmpty else { return }
        positionAtAnchorIfAvailable()
        let isNewPresentation = !panel.isVisible
        panel.orderFrontRegardless()
        publishAccessibilityLayout(isNewPresentation: isNewPresentation)
    }

    func hide() {
        precondition(Thread.isMainThread)
        panel.orderOut(nil)
        lastAnnouncedSnapshot = nil
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
    func performAccessibilitySelection(ordinal: Int) -> Bool {
        candidateButtons[ordinal]?.accessibilityPerformPress() ?? false
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
        panel.setAccessibilityRole(.group)
        panel.setAccessibilityLabel("五笔候选窗口")
    }

    private func configureContent() {
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.setAccessibilityElement(false)

        candidateStack.orientation = .vertical
        candidateStack.alignment = .leading
        candidateStack.spacing = 3
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateStack.setAccessibilityElement(false)

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

    private func publishAccessibilityLayout(isNewPresentation: Bool) {
        guard let first = candidateButtons.values.sorted(by: { $0.tag < $1.tag }).first else { return }
        let changedElements = candidateButtons.values.sorted(by: { $0.tag < $1.tag }) + [pageLabel]
        if isNewPresentation {
            NSAccessibility.post(element: panel, notification: .created)
        }
        NSAccessibility.post(element: panel,
                             notification: .layoutChanged,
                             userInfo: [.uiElements: changedElements])
        NSApplication.shared.setAccessibilityApplicationFocusedUIElement(first)
        first.setAccessibilityFocused(true)
        NSAccessibility.post(element: first, notification: .focusedUIElementChanged)
        if let snapshot = accessibilitySnapshot, snapshot != lastAnnouncedSnapshot {
            NSAccessibility.post(element: panel,
                                 notification: .announcementRequested,
                                 userInfo: [.announcement: snapshot.announcement,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
            lastAnnouncedSnapshot = snapshot
        }
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

private final class AccessibilityCandidateButton: NSButton {
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
}
