import Foundation

final class PersonalizationCoordinator {
    static let shared = PersonalizationCoordinator()

    private var candidatePageSize = 5
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

    private init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        if let url = bundle.url(forResource: "wb86", withExtension: "bin"),
           let image = try? DictionaryLoader.load(from: url) {
            index = DictionaryIndex(image: image)
        } else {
            index = nil
        }
        let root: URL? = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first?.appendingPathComponent(
                                            "org.macwubi.inputmethod", isDirectory: true
                                          )
        if let root, let writer = try? SnapshotWriter(rootURL: root) {
            userStore = try? UserLexiconStore(writer: writer)
            learningStore = try? LearningStore(writer: writer)
        } else {
            userStore = nil
            learningStore = nil
        }
    }

    func page(for code: InputCode, pageIndex: Int) throws -> CandidatePage {
        lock.lock()
        let includeLearning = learningEnabled && !privateMode
        lock.unlock()
        let records = index?.lookup(code) ?? []
        lock.lock()
        let pageSize = candidatePageSize
        lock.unlock()
        return try CandidateRanker(pageSize: pageSize).page(
            for: code,
            records: records,
            userEntries: userStore?.snapshot.entries.map {
                UserCandidateRanking(code: $0.code, text: $0.text, fixedRank: $0.fixedRank)
            } ?? [],
            learningRecords: learningStore?.snapshot.records.map {
                LearnedCandidateRanking(code: $0.code, candidateText: $0.candidateText,
                                        score: $0.score)
            } ?? [],
            learningEnabled: includeLearning,
            pageIndex: pageIndex
        )
    }

    func record(_ delta: LearningDelta) {
        lock.lock()
        let shouldLearn = learningEnabled && !privateMode
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
        lock.lock()
        candidatePageSize = settings.candidatePageSize
        learningEnabled = settings.learningEnabled
        let shouldLearn = settings.learningEnabled && !privateMode
        lock.unlock()
        learningStore?.isEnabled = shouldLearn
    }
}
