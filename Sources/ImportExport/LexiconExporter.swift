import Foundation

final class LexiconExporter {
    private let userStore: UserLexiconStore
    private let learningStore: LearningStore?

    init(userStore: UserLexiconStore, learningStore: LearningStore? = nil) {
        self.userStore = userStore
        self.learningStore = learningStore
    }

    func textData() throws -> Data {
        try LexiconTextCodec.encode(userStore.snapshot.entries.map {
            LexiconTransferEntry(code: $0.code, text: $0.text, fixedRank: $0.fixedRank)
        })
    }

    func archiveData(includeLearning: Bool) throws -> Data {
        let users = userStore.snapshot.entries.map {
            LexiconTransferEntry(code: $0.code, text: $0.text, fixedRank: $0.fixedRank)
        }
        let learning: [LexiconTransferLearning]? = includeLearning
            ? learningStore?.snapshot.records.map {
            LexiconTransferLearning(kind: $0.queryKey.kind,
                                    code: $0.queryKey.normalizedCode,
                                    candidateText: $0.candidateText,
                                    score: $0.score, decayEpoch: $0.decayEpoch)
            } : nil
        return try LexiconArchiveCodec.encode(MacWubiArchive(userLexicon: users,
                                                              learning: learning))
    }

    func write(_ data: Data, to destination: URL,
               validate: (Data) throws -> Void) throws {
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".macwubi-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        let staged = try Data(contentsOf: temporary)
        try validate(staged)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
