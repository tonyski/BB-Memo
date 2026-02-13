//
//  Memo.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class Memo {
    /// 业务稳定 ID：避免依赖 SwiftData 内部标识做跨会话逻辑
    var stableID: UUID = UUID()
    var content: String = ""
    /// 归一化内容哈希：用于导入去重与后续内容指纹能力
    var contentHash: String = ""
    var createdAt: Date = Foundation.Date.now
    var updatedAt: Date = Foundation.Date.now
    var isPinned: Bool = false
    var reminderDate: Date?
    var sourceType: String?
    var sourceIdentifier: String?
    var importedAt: Date?

    @Relationship(inverse: \Tag.memos)
    var tags: [Tag]?
    
    /// 判断内容是否为长文本
    var isLong: Bool { content.count > 180 }
    var tagsList: [Tag] { tags ?? [] }
    /// 稳定提醒标识，避免依赖持久化层内部 ID
    var reminderIdentifier: String { stableID.uuidString }
    /// 导入/同步幂等键
    var importIdentity: String {
        Memo.makeImportIdentity(
            sourceType: sourceType,
            sourceIdentifier: sourceIdentifier,
            contentHash: contentHash,
            content: content,
            createdAt: createdAt
        )
    }

    init(
        stableID: UUID = UUID(),
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false,
        reminderDate: Date? = nil,
        sourceType: String? = nil,
        sourceIdentifier: String? = nil,
        importedAt: Date? = nil,
        tags: [Tag] = []
    ) {
        self.stableID = stableID
        self.content = content
        self.contentHash = Memo.computeContentHash(for: content)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.reminderDate = reminderDate
        self.sourceType = sourceType
        self.sourceIdentifier = sourceIdentifier
        self.importedAt = importedAt
        self.tags = tags
    }

    static func computeContentHash(for content: String) -> String {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func makeImportIdentity(
        sourceType: String?,
        sourceIdentifier: String?,
        contentHash: String,
        content: String,
        createdAt: Date
    ) -> String {
        if let sourceType, let sourceIdentifier, !sourceIdentifier.isEmpty {
            return "\(sourceType):\(sourceIdentifier)"
        }
        let resolvedHash = contentHash.isEmpty ? computeContentHash(for: content) : contentHash
        return "hash:\(resolvedHash)|created:\(Int(createdAt.timeIntervalSince1970))"
    }

    func refreshContentHash() {
        contentHash = Memo.computeContentHash(for: content)
    }

}

enum MemoMaintenance {
    static func backfillDerivedFields(in context: ModelContext) throws {
        let memos = try context.fetch(FetchDescriptor<Memo>())
        var hasChanges = false
        var seenStableIDs = Set<UUID>()

        for memo in memos {
            if seenStableIDs.contains(memo.stableID) {
                memo.stableID = UUID()
                hasChanges = true
            }
            seenStableIDs.insert(memo.stableID)

            if memo.contentHash.isEmpty {
                memo.refreshContentHash()
                hasChanges = true
            }
            if memo.updatedAt < memo.createdAt {
                memo.updatedAt = memo.createdAt
                hasChanges = true
            }
        }

        if hasChanges {
            try context.save()
        }
    }
}
