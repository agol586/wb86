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

struct CandidateLayoutController {
    func layout(contentSize: NSSize, anchorTopLeft: NSPoint,
                environment: CandidateLayoutEnvironment) -> CandidateLayoutResult {
        let screen = environment.visibleFrames.first { $0.contains(anchorTopLeft) }
            ?? environment.visibleFrames.first
            ?? NSRect(origin: .zero, size: contentSize)
        let size = NSSize(width: min(max(1, contentSize.width), screen.width),
                          height: min(max(1, contentSize.height), screen.height))
        let proposed = NSPoint(x: anchorTopLeft.x, y: anchorTopLeft.y - size.height)
        let origin = NSPoint(x: min(max(proposed.x, screen.minX), screen.maxX - size.width),
                             y: min(max(proposed.y, screen.minY), screen.maxY - size.height))
        return CandidateLayoutResult(frame: NSRect(origin: origin, size: size),
                                     animates: !environment.reduceMotion,
                                     usesHighContrastBorder: environment.increaseContrast,
                                     backingScale: max(1, environment.backingScale))
    }
}
