enum CandidateQueryError: Error, Equatable {
    case invalidPageSize
    case pageOutOfRange
    case mismatchedCode
    case invalidRank
}

struct CandidateRankingPolicy: Equatable, Sendable {
    let settingsGeneration: UInt64
    let pageSize: Int
    let automaticFrequency: Bool

    init(settingsGeneration: UInt64, pageSize: Int, automaticFrequency: Bool) {
        precondition((5...9).contains(pageSize))
        self.settingsGeneration = settingsGeneration
        self.pageSize = pageSize
        self.automaticFrequency = automaticFrequency
    }
}

struct UserCandidateRanking: Equatable, Sendable {
    let code: InputCode
    let text: String
    let fixedRank: Int?
}

struct LearnedCandidateRanking: Equatable, Sendable {
    let queryKey: CandidateQueryKey
    let candidateText: String
    let score: Int

    init(code: InputCode, candidateText: String, score: Int) {
        self.init(queryKey: .wubi(code), candidateText: candidateText, score: score)
    }

    init(queryKey: CandidateQueryKey, candidateText: String, score: Int) {
        self.queryKey = queryKey
        self.candidateText = candidateText
        self.score = score
    }
}

struct CandidateRanker: Sendable {
    let policy: CandidateRankingPolicy
    var pageSize: Int { policy.pageSize }

    init(pageSize: Int) {
        policy = CandidateRankingPolicy(settingsGeneration: 0, pageSize: pageSize,
                                        automaticFrequency: true)
    }

    init(policy: CandidateRankingPolicy) {
        self.policy = policy
    }

    func page(for code: InputCode, records: [DictionaryEntryRecord],
              pageIndex: Int) throws -> CandidatePage {
        try page(for: code, records: records, userEntries: [], learningRecords: [],
                 learningEnabled: true, pageIndex: pageIndex)
    }

    func page(for code: InputCode, records: [DictionaryEntryRecord],
              userEntries: [UserCandidateRanking], learningRecords: [LearnedCandidateRanking],
              learningEnabled: Bool, pageIndex: Int) throws -> CandidatePage {
        guard (5...9).contains(pageSize) else { throw CandidateQueryError.invalidPageSize }
        guard pageIndex >= 0 else { throw CandidateQueryError.pageOutOfRange }
        guard records.allSatisfy({ $0.code == code }) else {
            throw CandidateQueryError.mismatchedCode
        }

        let matchingUsers = userEntries.filter { $0.code == code }
        let queryKey = CandidateQueryKey.wubi(code)
        let matchingLearning = learningEnabled
            ? learningRecords.filter { $0.queryKey == queryKey } : []
        var scores = [String: Int]()
        for record in matchingLearning {
            scores[record.candidateText] = max(scores[record.candidateText] ?? 0, record.score)
        }
        struct RankedValue {
            let text: String
            var source: CandidateSource
            var baseRank: Int
            var fixedRank: Int?
            var learnedScore: Int
        }
        var values = [String: RankedValue]()
        for record in records {
            guard let rank = Int(exactly: record.rank) else { throw CandidateQueryError.invalidRank }
            values[record.text] = RankedValue(text: record.text, source: .base,
                                              baseRank: rank, fixedRank: nil,
                                              learnedScore: scores[record.text] ?? 0)
        }
        for entry in matchingUsers {
            if var existing = values[entry.text] {
                existing.source = .user
                existing.fixedRank = entry.fixedRank
                existing.learnedScore = scores[entry.text] ?? 0
                values[entry.text] = existing
            } else {
                values[entry.text] = RankedValue(text: entry.text, source: .user,
                                                 baseRank: Int.max,
                                                 fixedRank: entry.fixedRank,
                                                 learnedScore: scores[entry.text] ?? 0)
            }
        }
        let ordered = values.values.sorted { lhs, rhs in
            if lhs.fixedRank != rhs.fixedRank {
                return (lhs.fixedRank ?? Int.max) < (rhs.fixedRank ?? Int.max)
            }
            if lhs.learnedScore != rhs.learnedScore { return lhs.learnedScore > rhs.learnedScore }
            if lhs.baseRank != rhs.baseRank { return lhs.baseRank < rhs.baseRank }
            return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
        }
        let start = pageIndex.multipliedReportingOverflow(by: pageSize)
        guard !start.overflow, start.partialValue <= ordered.count,
              pageIndex == 0 || start.partialValue < ordered.count else {
            throw CandidateQueryError.pageOutOfRange
        }
        let end = min(start.partialValue + pageSize, ordered.count)
        let slice = ordered[start.partialValue..<end]
        let candidates = try slice.enumerated().map { offset, value -> Candidate in
            return try Candidate(
                text: value.text,
                code: code,
                source: value.source,
                baseRank: value.baseRank,
                learnedScore: value.learnedScore,
                ordinal: offset + 1
            )
        }
        return try CandidatePage(
            items: candidates,
            pageIndex: pageIndex,
            pageSize: pageSize,
            totalCount: ordered.count
        )
    }

    func page(for code: InputCode, records: [DictionaryEntryRecord],
              userEntries: [UserCandidateRanking], learningRecords: [LearnedCandidateRanking],
              pageIndex: Int) throws -> CandidatePage {
        try page(for: code, records: records, userEntries: userEntries,
                 learningRecords: learningRecords,
                 learningEnabled: policy.automaticFrequency, pageIndex: pageIndex)
    }

    static func rank(candidates: [Candidate], learningEnabled: Bool) -> [Candidate] {
        candidates.sorted {
            let lhsTier = sourceTier($0.source)
            let rhsTier = sourceTier($1.source)
            if lhsTier != rhsTier { return lhsTier < rhsTier }
            let lhsScore = learningEnabled ? $0.learnedScore : 0
            let rhsScore = learningEnabled ? $1.learnedScore : 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if $0.baseRank != $1.baseRank { return $0.baseRank < $1.baseRank }
            return $0.text.utf8.lexicographicallyPrecedes($1.text.utf8)
        }
    }

    private static func sourceTier(_ source: CandidateSource) -> Int {
        source == .localPinyin ? 1 : 0
    }
}

struct CandidateQuery: Sendable {
    private let index: DictionaryIndex
    private let ranker: CandidateRanker

    init(index: DictionaryIndex, pageSize: Int) {
        self.index = index
        ranker = CandidateRanker(pageSize: pageSize)
    }

    func page(for code: InputCode, pageIndex: Int) throws -> CandidatePage {
        try ranker.page(for: code, records: index.lookup(code), pageIndex: pageIndex)
    }
}
