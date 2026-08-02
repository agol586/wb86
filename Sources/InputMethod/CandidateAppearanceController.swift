import AppKit

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
