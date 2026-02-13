//
//  TagUsageCounter.swift
//  BB
//
//  Created by Codex on 2026/2/12.
//

import Foundation
import SwiftData

/// 维护 Tag.usageCount，避免在列表中频繁读取关系数量造成性能抖动
enum TagUsageCounter {
    private static func modelKey(for tag: Tag) -> String {
        String(describing: tag.persistentModelID)
    }

    static func increment(_ tags: [Tag], by delta: Int = 1) {
        guard delta > 0 else { return }
        var seen = Set<String>()
        for tag in tags {
            let id = modelKey(for: tag)
            guard seen.insert(id).inserted else { continue }
            tag.usageCount += delta
        }
    }

    static func decrement(_ tags: [Tag], by delta: Int = 1) {
        guard delta > 0 else { return }
        var seen = Set<String>()
        for tag in tags {
            let id = modelKey(for: tag)
            guard seen.insert(id).inserted else { continue }
            tag.usageCount = max(0, tag.usageCount - delta)
        }
    }

    /// 用于编辑 Memo 时的标签变化：新增标签 +1，移除标签 -1
    static func applyDelta(oldTags: [Tag], newTags: [Tag]) {
        let oldIDs = Set(oldTags.map { modelKey(for: $0) })
        let newIDs = Set(newTags.map { modelKey(for: $0) })

        var seenNew = Set<String>()
        for tag in newTags {
            let id = modelKey(for: tag)
            guard seenNew.insert(id).inserted, !oldIDs.contains(id) else { continue }
            tag.usageCount += 1
        }
        var seenOld = Set<String>()
        for tag in oldTags {
            let id = modelKey(for: tag)
            guard seenOld.insert(id).inserted, !newIDs.contains(id) else { continue }
            tag.usageCount = max(0, tag.usageCount - 1)
        }
    }

    static func resyncAll(in context: ModelContext) throws {
        let tags = try context.fetch(FetchDescriptor<Tag>())
        var hasChanges = false
        for tag in tags {
            let normalized = Tag.normalize(tag.name).lowercased()
            if tag.normalizedName != normalized {
                tag.normalizedName = normalized
                hasChanges = true
            }
            let actual = tag.memosList.count
            if tag.usageCount != actual {
                tag.usageCount = actual
                hasChanges = true
            }
        }
        if hasChanges {
            try context.save()
        }
    }
}
