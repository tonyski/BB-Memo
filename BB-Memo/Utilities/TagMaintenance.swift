//
//  TagMaintenance.swift
//  BB
//
//  Created by Codex on 2026/2/12.
//

import SwiftData

/// 合并跨设备产生的同名标签，并维护规范化名称与使用计数。
enum TagMaintenance {
    /// 复用调用方读取的数据，使 Memo 与 Tag 的维护保持在同一个事务中。
    nonisolated static func reconcile(
        tags: [Tag],
        memos: [Memo],
        in context: ModelContext
    ) -> Bool {
        var hasChanges = false
        var tagsByNormalizedName: [String: [Tag]] = [:]

        for tag in tags {
            let normalized = Tag.normalizedKey(for: tag.name)
            if tag.normalizedName != normalized {
                tag.normalizedName = normalized
                hasChanges = true
            }
            if !normalized.isEmpty {
                tagsByNormalizedName[normalized, default: []].append(tag)
            }
        }

        var removedTags = Set<ObjectIdentifier>()
        for duplicates in tagsByNormalizedName.values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: canonicalOrder)
            guard let canonical = ordered.first else { continue }

            for duplicate in ordered.dropFirst() {
                merge(duplicate, into: canonical)
                removedTags.insert(ObjectIdentifier(duplicate))
                context.delete(duplicate)
                hasChanges = true
            }
        }

        var usageCounts: [ObjectIdentifier: Int] = [:]
        for memo in memos where !memo.isInRecycleBin {
            var seen = Set<ObjectIdentifier>()
            for tag in memo.tagsList {
                let identifier = ObjectIdentifier(tag)
                if seen.insert(identifier).inserted {
                    usageCounts[identifier, default: 0] += 1
                }
            }
        }

        for tag in tags where !removedTags.contains(ObjectIdentifier(tag)) {
            let actual = usageCounts[ObjectIdentifier(tag), default: 0]
            if tag.usageCount != actual {
                tag.usageCount = actual
                hasChanges = true
            }
        }

        return hasChanges
    }

    private nonisolated static func canonicalOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return String(describing: lhs.persistentModelID)
            < String(describing: rhs.persistentModelID)
    }

    private nonisolated static func merge(_ duplicate: Tag, into canonical: Tag) {
        let duplicateID = duplicate.persistentModelID
        let canonicalID = canonical.persistentModelID
        let affectedMemos = duplicate.memosList

        for memo in affectedMemos {
            var tags = memo.tagsList.filter {
                $0.persistentModelID != duplicateID
                    && $0.persistentModelID != canonicalID
            }
            tags.append(canonical)
            memo.tags = tags
        }
    }
}
