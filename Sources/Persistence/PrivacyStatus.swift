import Foundation

struct PrivacyDomainStatus: Equatable, Sendable {
    let domain: DataDomain
    let purpose: String
    let logicalLocation: String
    let byteCount: UInt64
    let schemaVersion: UInt32?
    let isPresent: Bool
}

final class PrivacyStatusProvider {
    private let writer: SnapshotWriter
    private let fileManager: FileManager
    init(writer: SnapshotWriter, fileManager: FileManager = .default) {
        self.writer = writer; self.fileManager = fileManager
    }

    func status() -> [PrivacyDomainStatus] {
        DataDomain.allCases.map { domain in
            let url = writer.currentURL(for: domain)
            let size = ((try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value ?? 0
            let snapshot = try? writer.load(domain)
            return PrivacyDomainStatus(domain: domain, purpose: purpose(domain),
                                       logicalLocation: "\(domain.directoryName)/current",
                                       byteCount: size, schemaVersion: snapshot?.schemaVersion,
                                       isPresent: snapshot != nil)
        }
    }

    private func purpose(_ domain: DataDomain) -> String {
        switch domain {
        case .settings: return "输入行为和外观设置"
        case .userLexicon: return "用户明确添加或导入的词条"
        case .learning: return "本地候选排序分数"
        }
    }
}
