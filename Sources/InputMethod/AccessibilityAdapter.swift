import AppKit

struct CandidateAccessibilityItem: Equatable, Sendable {
    let ordinal: Int
    let label: String
    let value: String
    let isSelected: Bool
}

struct CandidateAccessibilitySnapshot: Equatable, Sendable {
    let containerRole: NSAccessibility.Role
    let containerLabel: String
    let codeValue: String
    let candidates: [CandidateAccessibilityItem]
    let pageValue: String
    let announcement: String
}

enum AccessibilityAdapter {
    static func snapshot(page: CandidatePage) -> CandidateAccessibilitySnapshot {
        let pageNumber = page.pageIndex + 1
        let pageCount = max(1, (page.totalCount + page.pageSize - 1) / page.pageSize)
        var paging = "第 \(pageNumber) 页，共 \(pageCount) 页"
        if page.hasPrevious && page.hasNext { paging += "，可前后翻页" }
        else if page.hasPrevious { paging += "，可向前翻页" }
        else if page.hasNext { paging += "，可向后翻页" }
        let candidates = page.items.enumerated().map { index, candidate in
            CandidateAccessibilityItem(ordinal: candidate.ordinal,
                                       label: "候选 \(candidate.ordinal)",
                                       value: candidate.text,
                                       isSelected: index == 0)
        }
        let code = page.items.first?.queryKey.normalizedCode ?? ""
        let candidateAnnouncement = candidates.map { candidate in
            "候选 \(candidate.ordinal)，\(candidate.value)\(candidate.isSelected ? "，已选中" : "")。"
        }.joined()
        let announcement = "五笔候选窗口。编码 \(code)。\(paging)。\(candidateAnnouncement)"
        return CandidateAccessibilitySnapshot(
            containerRole: .group,
            containerLabel: "五笔候选",
            codeValue: code,
            candidates: candidates,
            pageValue: paging,
            announcement: announcement
        )
    }
}
