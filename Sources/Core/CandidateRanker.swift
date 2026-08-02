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
    static let maximumCandidatesPerTier = 64

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

    func mixedPage(for sequence: CompositionKeySequence,
                   wubiRecords: [DictionaryEntryRecord],
                   userEntries: [UserCandidateRanking],
                   pinyinCandidates: [PinyinLookupCandidate],
                   learningRecords: [LearnedCandidateRanking],
                   learningEnabled: Bool,
                   scriptConverter: ScriptConverter?,
                   outputScript: OutputScript,
                   pageIndex: Int) throws -> CandidatePage {
        guard (5...9).contains(pageSize) else { throw CandidateQueryError.invalidPageSize }
        guard pageIndex >= 0 else { throw CandidateQueryError.pageOutOfRange }

        struct MixedValue {
            let text: String
            let queryKey: CandidateQueryKey
            let source: CandidateSource
            let baseRank: Int
            let learnedScore: Int
            let wubiHint: InputCode?
        }
        struct WubiValue {
            let text: String
            var source: CandidateSource
            var baseRank: Int
            var fixedRank: Int?
            var learnedScore: Int
        }

        var wubiTier = [MixedValue]()
        if let code = sequence.wubiCode {
            guard wubiRecords.allSatisfy({ $0.code == code }),
                  userEntries.allSatisfy({ $0.code == code }) else {
                throw CandidateQueryError.mismatchedCode
            }
            let queryKey = CandidateQueryKey.wubi(code)
            let scores = learningScores(for: queryKey, in: learningRecords,
                                        enabled: learningEnabled)
            var values = [String: WubiValue]()
            for record in wubiRecords {
                guard let rank = Int(exactly: record.rank) else {
                    throw CandidateQueryError.invalidRank
                }
                values[record.text] = WubiValue(
                    text: record.text, source: .baseWubi, baseRank: rank,
                    fixedRank: nil, learnedScore: scores[record.text] ?? 0
                )
            }
            for entry in userEntries {
                if var existing = values[entry.text] {
                    existing.source = .userWubi
                    existing.fixedRank = entry.fixedRank
                    existing.learnedScore = scores[entry.text] ?? 0
                    values[entry.text] = existing
                } else {
                    values[entry.text] = WubiValue(
                        text: entry.text, source: .userWubi, baseRank: Int.max,
                        fixedRank: entry.fixedRank, learnedScore: scores[entry.text] ?? 0
                    )
                }
            }
            let ordered = values.values.sorted { lhs, rhs in
                if lhs.fixedRank != rhs.fixedRank {
                    return (lhs.fixedRank ?? Int.max) < (rhs.fixedRank ?? Int.max)
                }
                if lhs.learnedScore != rhs.learnedScore {
                    return lhs.learnedScore > rhs.learnedScore
                }
                if lhs.baseRank != rhs.baseRank { return lhs.baseRank < rhs.baseRank }
                return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
            }
            wubiTier = ordered.prefix(Self.maximumCandidatesPerTier).map {
                MixedValue(text: $0.text, queryKey: queryKey, source: $0.source,
                           baseRank: $0.baseRank, learnedScore: $0.learnedScore,
                           wubiHint: code)
            }
        } else if !wubiRecords.isEmpty || !userEntries.isEmpty {
            throw CandidateQueryError.mismatchedCode
        }

        let pinyinKey = CandidateQueryKey(kind: .pinyin, code: sequence.letters)!
        let pinyinScores = learningScores(for: pinyinKey, in: learningRecords,
                                          enabled: learningEnabled)
        let pinyinTier = pinyinCandidates.sorted { lhs, rhs in
            let lhsScore = pinyinScores[lhs.text] ?? 0
            let rhsScore = pinyinScores[rhs.text] ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.baseRank != rhs.baseRank { return lhs.baseRank < rhs.baseRank }
            return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
        }.prefix(Self.maximumCandidatesPerTier).map {
            MixedValue(text: $0.text, queryKey: pinyinKey, source: .localPinyin,
                       baseRank: $0.baseRank, learnedScore: pinyinScores[$0.text] ?? 0,
                       wubiHint: $0.wubiHint)
        }

        var seenDisplayText = Set<String>()
        var merged = [MixedValue]()
        merged.reserveCapacity(wubiTier.count + pinyinTier.count)
        for value in wubiTier + pinyinTier {
            let displayText = scriptConverter?.convert(value.text, to: outputScript) ?? value.text
            guard seenDisplayText.insert(displayText).inserted else { continue }
            merged.append(MixedValue(
                text: displayText, queryKey: value.queryKey, source: value.source,
                baseRank: value.baseRank, learnedScore: value.learnedScore,
                wubiHint: value.wubiHint
            ))
        }

        let start = pageIndex.multipliedReportingOverflow(by: pageSize)
        guard !start.overflow, start.partialValue <= merged.count,
              pageIndex == 0 || start.partialValue < merged.count else {
            throw CandidateQueryError.pageOutOfRange
        }
        let end = min(start.partialValue + pageSize, merged.count)
        let items = try merged[start.partialValue..<end].enumerated().map { offset, value in
            try Candidate(text: value.text, queryKey: value.queryKey,
                          source: value.source, baseRank: value.baseRank,
                          learnedScore: value.learnedScore, ordinal: offset + 1,
                          wubiHint: value.wubiHint)
        }
        return try CandidatePage(items: items, pageIndex: pageIndex,
                                 pageSize: pageSize, totalCount: merged.count)
    }

    private func learningScores(for queryKey: CandidateQueryKey,
                                in records: [LearnedCandidateRanking],
                                enabled: Bool) -> [String: Int] {
        guard enabled else { return [:] }
        var scores = [String: Int]()
        for record in records where record.queryKey == queryKey {
            scores[record.candidateText] = max(scores[record.candidateText] ?? 0, record.score)
        }
        return scores
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
