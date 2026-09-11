import AppKit

struct CandidateLayoutEnvironment: Equatable, Sendable {
    let visibleFrames: [NSRect]
    let reduceMotion: Bool
    let increaseContrast: Bool
    let backingScale: CGFloat
}

struct CandidateLayoutResult: Equatable, Sendable {
    let frame: NSRect
    let animates: Bool
    let usesHighContrastBorder: Bool
    let backingScale: CGFloat
}

struct CandidateRowPresentation: Equatable, Sendable {
    let title: String
    let visibleHint: String?
}

struct CandidateLayoutController {
    func rowPresentation(for candidate: Candidate, showsCodeHint: Bool,
                         maximumWidth: CGFloat, font: NSFont) -> CandidateRowPresentation {
        let body = "\(candidate.ordinal)  \(candidate.text)"
        let candidateHint = showsCodeHint ? visibleCodeHint(for: candidate) : nil
        guard let hint = candidateHint else {
            return CandidateRowPresentation(title: body, visibleHint: nil)
        }
        let withHint = body + "  " + hint
        let measuredWidth = (withHint as NSString).size(withAttributes: [.font: font]).width
        let visibleHint = measuredWidth <= max(1, maximumWidth) ? hint : nil
        return CandidateRowPresentation(
            title: visibleHint == nil ? body : withHint,
            visibleHint: visibleHint
        )
    }

    private func visibleCodeHint(for candidate: Candidate) -> String? {
        guard let fullHint = candidate.wubiHint?.letters else { return nil }
        guard candidate.queryKey.kind == .wubi else { return fullHint }
        let typed = candidate.queryKey.normalizedCode
        guard fullHint.hasPrefix(typed), fullHint.utf8.count > typed.utf8.count else {
            return nil
        }
        return String(fullHint.dropFirst(typed.count))
    }

    func layout(contentSize: NSSize, anchorRect: NSRect,
                environment: CandidateLayoutEnvironment) -> CandidateLayoutResult {
        let normalizedAnchor = anchorRect.standardized
        let anchorPoint = NSPoint(x: normalizedAnchor.midX, y: normalizedAnchor.midY)
        let screen = environment.visibleFrames.first { $0.contains(anchorPoint) }
            ?? environment.visibleFrames.first
            ?? NSRect(origin: .zero, size: contentSize)
        let spacing: CGFloat = 4
        let availableBelow = max(0, normalizedAnchor.minY - spacing - screen.minY)
        let availableAbove = max(0, screen.maxY - normalizedAnchor.maxY - spacing)
        let placeBelow = contentSize.height <= availableBelow
            || (contentSize.height > availableAbove && availableBelow >= availableAbove)
        let availableHeight = placeBelow ? availableBelow : availableAbove
        let size = NSSize(width: min(max(1, contentSize.width), screen.width),
                          height: min(max(1, contentSize.height), max(1, availableHeight)))
        let proposedY = placeBelow
            ? normalizedAnchor.minY - spacing - size.height
            : normalizedAnchor.maxY + spacing
        let origin = NSPoint(
            x: min(max(normalizedAnchor.minX, screen.minX), screen.maxX - size.width),
            y: min(max(proposedY, screen.minY), screen.maxY - size.height)
        )
        return CandidateLayoutResult(frame: NSRect(origin: origin, size: size),
                                     animates: !environment.reduceMotion,
                                     usesHighContrastBorder: environment.increaseContrast,
                                     backingScale: max(1, environment.backingScale))
    }
}
