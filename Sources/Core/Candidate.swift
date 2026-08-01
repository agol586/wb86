enum CandidateSource: String, Codable, Sendable {
    case base
    case user
}

enum CandidateValidationError: Error, Equatable {
    case emptyText
    case invalidBaseRank
    case learnedScoreOutOfBounds
    case invalidOrdinal
    case invalidPageSize
    case invalidPageIndex
    case invalidTotalCount
    case tooManyItems
    case inconsistentCode
    case inconsistentOrdinal
}

struct Candidate: Equatable, Hashable, Sendable {
    static let learnedScoreBounds = -1_000_000...1_000_000

    let text: String
    let code: InputCode
    let source: CandidateSource
    let baseRank: Int
    let learnedScore: Int
    let ordinal: Int

    init(text: String, code: InputCode, source: CandidateSource, baseRank: Int,
         learnedScore: Int, ordinal: Int) throws {
        guard !text.isEmpty else { throw CandidateValidationError.emptyText }
        guard baseRank >= 0 else { throw CandidateValidationError.invalidBaseRank }
        guard Self.learnedScoreBounds.contains(learnedScore) else {
            throw CandidateValidationError.learnedScoreOutOfBounds
        }
        guard (1...9).contains(ordinal) else { throw CandidateValidationError.invalidOrdinal }
        self.text = text
        self.code = code
        self.source = source
        self.baseRank = baseRank
        self.learnedScore = learnedScore
        self.ordinal = ordinal
    }
}

struct CandidatePage: Equatable, Sendable {
    let items: [Candidate]
    let pageIndex: Int
    let pageSize: Int
    let totalCount: Int

    init(items: [Candidate], pageIndex: Int, pageSize: Int, totalCount: Int) throws {
        guard (5...9).contains(pageSize) else { throw CandidateValidationError.invalidPageSize }
        guard pageIndex >= 0 else { throw CandidateValidationError.invalidPageIndex }
        guard totalCount >= 0 else { throw CandidateValidationError.invalidTotalCount }
        guard items.count <= pageSize else { throw CandidateValidationError.tooManyItems }
        let pageStart = pageIndex.multipliedReportingOverflow(by: pageSize)
        guard !pageStart.overflow, pageStart.partialValue <= totalCount,
              pageStart.partialValue + items.count <= totalCount else {
            throw CandidateValidationError.invalidTotalCount
        }
        if let code = items.first?.code, items.contains(where: { $0.code != code }) {
            throw CandidateValidationError.inconsistentCode
        }
        guard items.enumerated().allSatisfy({ $0.element.ordinal == $0.offset + 1 }) else {
            throw CandidateValidationError.inconsistentOrdinal
        }
        self.items = items
        self.pageIndex = pageIndex
        self.pageSize = pageSize
        self.totalCount = totalCount
    }

    var hasPrevious: Bool { pageIndex > 0 }
    var hasNext: Bool { (pageIndex + 1) * pageSize < totalCount }
}
