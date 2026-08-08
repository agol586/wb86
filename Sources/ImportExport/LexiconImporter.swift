import Foundation

enum ImportErrorCategory: String, Codable, Sendable {
    case invalidRecord
    case duplicate
}

struct ImportReport: Equatable, Sendable {
    let acceptedCount: Int
    let mergedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let errorCategories: [ImportErrorCategory: Int]
}

final class LexiconImporter {
    private let store: UserLexiconStore
    private let learningStore: LearningStore?

    init(store: UserLexiconStore, learningStore: LearningStore? = nil) {
        self.store = store
        self.learningStore = learningStore
    }

    func importText(_ data: Data) throws -> ImportReport {
        let decoded = try LexiconTextCodec.decode(data)
        let report = try merge(decoded.entries)
        var categories = [ImportErrorCategory: Int]()
        if decoded.failedCount > 0 { categories[.invalidRecord] = decoded.failedCount }
        if decoded.mergedCount > 0 { categories[.duplicate] = decoded.mergedCount }
        return ImportReport(acceptedCount: report.added,
                            mergedCount: report.merged + decoded.mergedCount,
                            skippedCount: decoded.skippedCount,
                            failedCount: decoded.failedCount,
                            errorCategories: categories)
    }

    func importArchive(_ data: Data) throws -> ImportReport {
        let archive = try LexiconArchiveCodec.decode(data)
        let learning = try archive.learning?.map { item -> LearningRecord in
            guard (item.kind ?? .wubi) != .directInput,
                  let queryKey = CandidateQueryKey(kind: item.kind ?? .wubi,
                                                   code: item.code) else {
                throw LexiconCodecError.invalidRecord
            }
            let key = try LearningKey(queryKey: queryKey, candidateText: item.candidateText)
            return LearningRecord(key: key, score: item.score, decayEpoch: item.decayEpoch)
        }
        let result = try merge(archive.userLexicon)
        if let learning { try learningStore?.mergeImported(learning) }
        return ImportReport(acceptedCount: result.added, mergedCount: result.merged,
                            skippedCount: 0, failedCount: 0, errorCategories: [:])
    }

    private func merge(_ entries: [LexiconTransferEntry]) throws -> (added: Int, merged: Int) {
        let validated = try entries.map {
            try UserLexiconEntry(code: $0.code, text: $0.text, fixedRank: $0.fixedRank,
                                 createdBy: .imported)
        }
        return try store.mergeImported(validated)
    }
}
