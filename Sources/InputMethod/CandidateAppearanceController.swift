import AppKit

enum CandidateTypography {
    static func candidatePointSize(for scale: Double) -> CGFloat {
        let bounded = min(2, max(0.8, scale))
        if bounded <= 1 {
            return CGFloat(14 + (bounded - 1) * 5)
        }
        return CGFloat(14 + (bounded - 1) * 3)
    }

    static func pagePointSize(for scale: Double) -> CGFloat {
        let bounded = min(2, max(0.8, scale))
        return CGFloat(11 + (bounded - 1) * 2)
    }

    static func displayName(for scale: Double) -> String {
        switch scale {
        case ..<0.9: return "较小"
        case ..<1.15: return "标准"
        case ..<1.45: return "较大"
        case ..<1.8: return "大"
        default: return "特大"
        }
    }
}

protocol CandidateAppearanceApplying: CandidatePresenting {
    func apply(settings: InputSettings)
}

struct CandidatePreview: Equatable, Sendable {
    let items: [String]
    let layout: CandidateLayout
    let fontScale: Double
}

final class CandidateAppearanceController {
    func preview(settings: InputSettings) -> CandidatePreview {
        CandidatePreview(items: ["1  示例", "2  示例", "3  示例"],
                         layout: settings.candidateLayout,
                         fontScale: settings.candidateFontScale)
    }

    func apply(settings: InputSettings, to presenter: CandidateAppearanceApplying) {
        presenter.apply(settings: settings)
    }
}
