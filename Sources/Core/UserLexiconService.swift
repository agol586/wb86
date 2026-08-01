enum UserLexiconMutationKind: Equatable, Sendable {
    case added
    case merged
    case edited
    case deleted
    case unchanged
}

struct UserLexiconMutationResult: Equatable, Sendable {
    let kind: UserLexiconMutationKind
    let generation: UInt64
    let totalCount: Int
}

final class UserLexiconService {
    private let store: UserLexiconStore

    init(store: UserLexiconStore) { self.store = store }

    func add(code: InputCode, text: String, fixedRank: Int? = nil,
             origin: UserLexiconEntryOrigin = .manual) throws -> UserLexiconMutationResult {
        let outcome = try store.upsert(code: code, text: text,
                                       fixedRank: fixedRank, createdBy: origin)
        return result(outcome == .added ? .added : .merged)
    }

    func edit(id: String, code: InputCode, text: String,
              fixedRank: Int?) throws -> UserLexiconMutationResult {
        try store.edit(id: id, code: code, text: text, fixedRank: fixedRank)
        return result(.edited)
    }

    func delete(id: String) throws -> UserLexiconMutationResult {
        result(try store.delete(id: id) ? .deleted : .unchanged)
    }

    func search(_ query: String, limit: Int = 100) -> [UserLexiconEntry] {
        store.search(query, limit: limit)
    }

    var snapshot: UserLexiconSnapshot { store.snapshot }

    private func result(_ kind: UserLexiconMutationKind) -> UserLexiconMutationResult {
        UserLexiconMutationResult(kind: kind, generation: store.snapshot.generation,
                                  totalCount: store.snapshot.entries.count)
    }
}
