import Foundation

final class PersonalizationCoordinator {
    static let shared = PersonalizationCoordinator()

    private let index: DictionaryIndex?
    private let userStore: UserLexiconStore?
    private let learningStore: LearningStore?
    private let lock = NSLock()
    private(set) var privateMode = false
    private(set) var learningEnabled = true

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
        let loadedIndex: DictionaryIndex?
        if let url = bundle.url(forResource: "wb86", withExtension: "bin"),
           let image = try? DictionaryLoader.load(from: url) {
            loadedIndex = DictionaryIndex(image: image)
        } else {
            loadedIndex = nil
        }
        let root: URL? = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first?.appendingPathComponent(
                                            "org.macwubi.inputmethod", isDirectory: true
                                          )
        if let root, let writer = try? SnapshotWriter(rootURL: root) {
            self.init(index: loadedIndex,
                      userStore: try? UserLexiconStore(writer: writer),
                      learningStore: try? LearningStore(writer: writer))
        } else {
            self.init(index: loadedIndex, userStore: nil, learningStore: nil)
        }
    }

    init(index: DictionaryIndex?, userStore: UserLexiconStore?,
         learningStore: LearningStore?) {
        self.index = index
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
        let records = index?.lookup(code) ?? []
        let effectivePolicy = CandidateRankingPolicy(
            settingsGeneration: policy.settingsGeneration,
            pageSize: policy.pageSize,
            automaticFrequency: includeLearning
        )
        return try CandidateRanker(policy: effectivePolicy).page(
            for: code,
            records: records,
            userEntries: userStore?.snapshot.entries.map {
                UserCandidateRanking(code: $0.code, text: $0.text, fixedRank: $0.fixedRank)
            } ?? [],
            learningRecords: learningStore?.snapshot.records.map {
                LearnedCandidateRanking(code: $0.code, candidateText: $0.candidateText,
                                        score: $0.score)
            } ?? [],
            pageIndex: pageIndex
        )
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
        try? learningStore?.recordSelection(code: delta.code,
                                            candidateText: delta.candidateText,
                                            amount: delta.amount)
    }

    func setPolicy(privateMode: Bool, learningEnabled: Bool) {
        lock.lock()
        self.privateMode = privateMode
        self.learningEnabled = learningEnabled
        lock.unlock()
        learningStore?.isEnabled = learningEnabled && !privateMode
    }

    func apply(settings: InputSettings) {
        // Semantic settings are supplied explicitly by each session's frozen policy.
        // Runtime privacy/learning controls remain independent and are managed by setPolicy.
    }
}
