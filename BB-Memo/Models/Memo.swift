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
    /// 兼容已有 CloudKit 存储的历史字段；业务逻辑统一使用 `deletedAt`，本字段只做镜像。
    /// 注意：它遮蔽了 `PersistentModel.isDeleted`（SwiftData 的删除状态），
    /// 在具体类型 `Memo` 上读到的是回收站镜像而非框架状态。
    /// 不能直接改名：改名会变更 CloudKit 字段（CD_isDeleted），需要重新部署生产环境 schema。
    var isDeleted: Bool = false
    var deletedAt: Date?
    var reminderDate: Date?
    var sourceType: String?
    var sourceIdentifier: String?
    var importedAt: Date?

    @Relationship(inverse: \Tag.memos)
    var tags: [Tag]?
    
    /// 判断内容是否为长文本
    var isLong: Bool { content.count > 180 }
    var tagsList: [Tag] { (tags ?? []).sorted(by: Tag.stableDisplayOrder) }
    /// 稳定提醒标识，避免依赖持久化层内部 ID
    var reminderIdentifier: String { stableID.uuidString }
    /// 回收站状态判定（单一可信来源）
    var isInRecycleBin: Bool { deletedAt != nil }
    /// 导入/同步幂等键
    var importIdentity: String {
        Memo.makeImportIdentity(
            sourceType: sourceType,
            sourceIdentifier: sourceIdentifier,
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
        deletedAt: Date? = nil,
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
        self.isDeleted = deletedAt != nil
        self.deletedAt = deletedAt
        self.reminderDate = reminderDate
        self.sourceType = sourceType
        self.sourceIdentifier = sourceIdentifier
        self.importedAt = importedAt
        self.tags = tags
    }

    nonisolated static func computeContentHash(for content: String) -> String {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func makeImportIdentity(
        sourceType: String?,
        sourceIdentifier: String?,
        content: String,
        createdAt: Date
    ) -> String {
        if let sourceType, let sourceIdentifier, !sourceIdentifier.isEmpty {
            return "\(sourceType):\(sourceIdentifier)"
        }
        return "hash:\(computeContentHash(for: content))|created:\(Int(createdAt.timeIntervalSince1970))"
    }

    func refreshContentHash() {
        contentHash = Memo.computeContentHash(for: content)
    }

}

enum MemoMaintenance {
    /// 修复旧模型字段和派生值。由调用方统一读取并保存，避免维护流程重复查询。
    ///
    /// 每台设备都会独立执行本方法并把结果同步出去，因此所有修复都必须是确定性的：
    /// 同样的数据在任何设备上都得出同样的结果，否则设备之间会反复覆盖对方。
    nonisolated static func reconcile(_ memos: [Memo]) -> Bool {
        var hasChanges = false
        var seenStableIDs = Set<UUID>()

        // 按跨设备一致的字段排序后再去重，保证各设备保留同一条记录的 stableID。
        let ordered = memos.sorted(by: stableIdentityOrder)
        for memo in ordered {
            if seenStableIDs.contains(memo.stableID) {
                // 完全相同的重复记录会派生出相同 ID，继续从新 ID 派生直到不冲突。
                var candidate = deterministicStableID(for: memo, base: memo.stableID)
                while seenStableIDs.contains(candidate) {
                    candidate = deterministicStableID(for: memo, base: candidate)
                }
                memo.stableID = candidate
                hasChanges = true
            }
            seenStableIDs.insert(memo.stableID)
        }

        for memo in memos {
            let expectedContentHash = Memo.computeContentHash(for: memo.content)
            if memo.contentHash != expectedContentHash {
                memo.contentHash = expectedContentHash
                hasChanges = true
            }
            if memo.updatedAt < memo.createdAt {
                memo.updatedAt = memo.createdAt
                hasChanges = true
            }
            // `deletedAt` 是回收站状态的唯一依据，`isDeleted` 只跟随它。
            // 两个字段在 CloudKit 中独立合并，并发删除/恢复后可能不一致；
            // 旧逻辑在不一致时一律判为"已删除"，会把刚恢复的笔记重新放回回收站。
            let shouldBeDeleted = memo.deletedAt != nil
            if memo.isDeleted != shouldBeDeleted {
                memo.isDeleted = shouldBeDeleted
                hasChanges = true
            }
        }

        return hasChanges
    }

    /// 只用跨设备完全一致的字段排序（不用日期：CloudKit 会把日期截到毫秒，
    /// 创建设备本地却是完整精度）。完全相同的记录无论怎么排结果都等价。
    private nonisolated static func stableIdentityOrder(_ lhs: Memo, _ rhs: Memo) -> Bool {
        let lhsHash = Memo.computeContentHash(for: lhs.content)
        let rhsHash = Memo.computeContentHash(for: rhs.content)
        if lhsHash != rhsHash { return lhsHash < rhsHash }
        return lhs.sourceIdentifier ?? "" < rhs.sourceIdentifier ?? ""
    }

    /// 由记录内容派生新 ID：多台设备独立修复同一组重复时会得到相同结果。
    private nonisolated static func deterministicStableID(for memo: Memo, base: UUID) -> UUID {
        let seed = "\(base.uuidString)|" + Memo.computeContentHash(for: memo.content)
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 风格
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
