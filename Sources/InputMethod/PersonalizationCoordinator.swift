import Foundation

enum PersonalizationOperationError: Error, Equatable {
    case unavailable
}

final class PersonalizationCoordinator {
    static let shared = PersonalizationCoordinator()

    private let index: DictionaryIndex?
    private let pinyinIndex: PinyinDictionaryIndex?
    private let userStore: UserLexiconStore?
    private let learningStore: LearningStore?
    private let lock = NSLock()
    private(set) var privateMode = false
    private(set) var learningEnabled = true

    var hasLocalPinyin: Bool { pinyinIndex != nil }

    var userLexiconService: UserLexiconService? {
        userStore.map(UserLexiconService.init(store:))
    }

    var lexiconImporter: LexiconImporter? {
        userStore.map { LexiconImporter(store: $0, learningStore: learningStore) }
    }

    var lexiconExporter: LexiconExporter? {
        userStore.map { LexiconExporter(userStore: $0, learningStore: learningStore) }
    }

    private convenience init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        let baseImage: BaseDictionaryImage?
        let loadedIndex: DictionaryIndex?
        if let url = bundle.url(forResource: "wb86", withExtension: "bin"),
           let image = try? DictionaryLoader.load(from: url) {
            baseImage = image
            loadedIndex = DictionaryIndex(image: image)
        } else {
            baseImage = nil
            loadedIndex = nil
        }
        let loadedPinyinIndex: PinyinDictionaryIndex?
        if let baseImage,
           let url = bundle.url(forResource: "pinyin-simp", withExtension: "bin"),
           let image = try? PinyinDictionaryLoader.load(from: url, wb86Image: baseImage) {
            loadedPinyinIndex = PinyinDictionaryIndex(image: image)
        } else {
            loadedPinyinIndex = nil
        }
        let root: URL? = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first?.appendingPathComponent(
                                            "org.macwubi.inputmethod", isDirectory: true
                                          )
        if let root, let writer = try? SnapshotWriter(rootURL: root) {
            self.init(index: loadedIndex, pinyinIndex: loadedPinyinIndex,
                      userStore: try? UserLexiconStore(writer: writer),
                      learningStore: try? LearningStore(writer: writer))
        } else {
            self.init(index: loadedIndex, pinyinIndex: loadedPinyinIndex,
                      userStore: nil, learningStore: nil)
        }
    }

    init(index: DictionaryIndex?, pinyinIndex: PinyinDictionaryIndex? = nil,
         userStore: UserLexiconStore?,
         learningStore: LearningStore?) {
        self.index = index
        self.pinyinIndex = pinyinIndex
        self.userStore = userStore
        self.learningStore = learningStore
    }

    func page(for code: InputCode, pageIndex: Int) throws -> CandidatePage {
        lock.lock()
        let legacyPolicy = CandidateRankingPolicy(settingsGeneration: 0, pageSize: 5,
                                                  automaticFrequency: learningEnabled)
        lock.unlock()
        return try page(for: code, pageIndex: pageIndex, policy: legacyPolicy)
    }

    func page(for code: InputCode, pageIndex: Int,
              policy: CandidateRankingPolicy) throws -> CandidatePage {
        lock.lock()
        let includeLearning = policy.automaticFrequency && learningEnabled && !privateMode
        lock.unlock()
        let records = (2...3).contains(code.length)
            ? index?.records(matchingPrefix: code,
                             maximumCount: DictionaryIndex.maximumAssociationRecords) ?? []
            : index?.lookup(code) ?? []
        let effectivePolicy = CandidateRankingPolicy(
            settingsGeneration: policy.settingsGeneration,
            pageSize: policy.pageSize,
            automaticFrequency: includeLearning,
            extendedCharacterSetEnabled: policy.extendedCharacterSetEnabled
        )
        let learningRecords: [LearnedCandidateRanking]
        if includeLearning, let snapshot = learningStore?.snapshot {
            learningRecords = snapshot.records.map {
                LearnedCandidateRanking(queryKey: $0.queryKey,
                                        candidateText: $0.candidateText,
                                        score: $0.score)
            }
        } else {
            learningRecords = []
        }
        return try CandidateRanker(policy: effectivePolicy).page(
            for: code,
            records: records,
            userEntries: userStore?.snapshot.entries.map {
                UserCandidateRanking(code: $0.code, text: $0.text, fixedRank: $0.fixedRank)
            } ?? [],
            learningRecords: learningRecords,
            pageIndex: pageIndex
        )
    }

    func page(for sequence: CompositionKeySequence, pageIndex: Int,
              policy: CandidateRankingPolicy, mode: InputMode,
              mixedPinyinEnabled: Bool, scriptConverter: ScriptConverter?) throws
        -> SequenceQueryResult {
        lock.lock()
        let includeLearning = policy.automaticFrequency && learningEnabled && !privateMode
        lock.unlock()
        let effectivePolicy = CandidateRankingPolicy(
            settingsGeneration: policy.settingsGeneration,
            pageSize: policy.pageSize,
            automaticFrequency: includeLearning,
            extendedCharacterSetEnabled: policy.extendedCharacterSetEnabled
        )
        let learningRecords = includeLearning ? currentLearningRecords() : []
        let wubiRecords: [DictionaryEntryRecord] = sequence.wubiCode.map { code in
            guard (2...3).contains(code.length) else { return index?.lookup(code) ?? [] }
            return index?.records(matchingPrefix: code,
                                  maximumCount: DictionaryIndex.maximumAssociationRecords) ?? []
        } ?? []
        let userEntries: [UserCandidateRanking]
        if let code = sequence.wubiCode {
            userEntries = userStore?.snapshot.entries.compactMap { entry in
                guard entry.code == code else { return nil }
                return UserCandidateRanking(code: entry.code, text: entry.text,
                                            fixedRank: entry.fixedRank)
            } ?? []
        } else {
            userEntries = []
        }

        let pinyinResult: (state: PinyinQueryState,
                           candidates: [PinyinLookupCandidate])
        if mixedPinyinEnabled, let pinyinIndex {
            pinyinResult = try pinyinCandidates(for: sequence, index: pinyinIndex)
        } else {
            pinyinResult = (.unavailable, [])
        }
        let page = try CandidateRanker(policy: effectivePolicy).mixedPage(
            for: sequence,
            wubiRecords: wubiRecords,
            userEntries: userEntries,
            pinyinCandidates: pinyinResult.candidates,
            learningRecords: learningRecords,
            learningEnabled: includeLearning,
            scriptConverter: scriptConverter,
            outputScript: mode.script,
            pageIndex: pageIndex
        )
        return SequenceQueryResult(pinyinState: pinyinResult.state, page: page)
    }

    func record(_ delta: LearningDelta) {
        lock.lock()
        let legacyPolicy = CandidateRankingPolicy(settingsGeneration: 0, pageSize: 5,
                                                  automaticFrequency: learningEnabled)
        lock.unlock()
        record(delta, policy: legacyPolicy)
    }

    func record(_ delta: LearningDelta, policy: CandidateRankingPolicy) {
        lock.lock()
        let shouldLearn = policy.automaticFrequency && learningEnabled && !privateMode
        lock.unlock()
        guard shouldLearn else { return }
        learningStore?.isEnabled = true
        guard let key = try? LearningKey(queryKey: delta.queryKey,
                                         candidateText: delta.candidateText) else { return }
        try? learningStore?.recordSelection(key: key, amount: delta.amount)
    }

    func setPolicy(privateMode: Bool, learningEnabled: Bool) {
        lock.lock()
        self.privateMode = privateMode
        self.learningEnabled = learningEnabled
        lock.unlock()
        learningStore?.isEnabled = learningEnabled && !privateMode
    }

    @discardableResult
    func clearLearning() throws -> Int {
        guard let learningStore else { throw PersonalizationOperationError.unavailable }
        let removedCount = learningStore.snapshot.records.count
        try learningStore.clear()
        return removedCount
    }

    func apply(settings: InputSettings) {
        // Semantic settings are supplied explicitly by each session's frozen policy.
        // Runtime privacy/learning controls remain independent and are managed by setPolicy.
    }

    private func currentLearningRecords() -> [LearnedCandidateRanking] {
        learningStore?.snapshot.records.map {
            LearnedCandidateRanking(queryKey: $0.queryKey,
                                    candidateText: $0.candidateText,
                                    score: $0.score)
        } ?? []
    }

    private func pinyinCandidates(for sequence: CompositionKeySequence,
                                  index: PinyinDictionaryIndex) throws
        -> (state: PinyinQueryState, candidates: [PinyinLookupCandidate]) {
        guard index.prefixExists(sequence) else { return (.noMatch, []) }
        var pageIndex = 0
        var page = try index.page(for: sequence, pageIndex: pageIndex, pageSize: 9)
        guard page.totalCount > 0 else {
            return (.viablePrefix, try index.predictions(for: sequence))
        }
        var candidates = page.items
        while page.hasNext {
            pageIndex += 1
            page = try index.page(for: sequence, pageIndex: pageIndex, pageSize: 9)
            candidates.append(contentsOf: page.items)
        }
        guard candidates.count <= CandidateRanker.maximumCandidatesPerTier else {
            throw PinyinDictionaryQueryError.corruptImage
        }
        return (.exactMatch, candidates)
    }
}
