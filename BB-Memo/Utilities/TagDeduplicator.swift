//
//  TagDeduplicator.swift
//  BB-Memo
//

import Foundation
import SwiftData

/// 合并重复标签：按 normalizedName 归并到同一 Tag
enum TagDeduplicator {
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> Int {
        let allTags = try context.fetch(FetchDescriptor<Tag>())
        var grouped: [String: [Tag]] = [:]

        for tag in allTags {
            let normalized = Tag.normalize(tag.name).lowercased()
            if tag.normalizedName != normalized {
                tag.normalizedName = normalized
            }
            grouped[normalized, default: []].append(tag)
        }

        var mergedCount = 0

        for (_, tags) in grouped {
            guard tags.count > 1 else { continue }

            let sorted = tags.sorted { lhs, rhs in
                if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
                return lhs.createdAt < rhs.createdAt
            }
            guard let canonical = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                for memo in duplicate.memosList {
                    var currentTags = memo.tagsList.filter {
                        $0.persistentModelID != duplicate.persistentModelID
                    }
                    let containsCanonical = currentTags.contains {
                        $0.persistentModelID == canonical.persistentModelID
                    }
                    if !containsCanonical {
                        currentTags.append(canonical)
                    }
                    memo.tags = currentTags
                }
                context.delete(duplicate)
                mergedCount += 1
            }
        }

        if mergedCount > 0 {
            try context.save()
        }
        return mergedCount
    }
}
