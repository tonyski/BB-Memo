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
    private static let backfillKey = "tag_usage_count_backfill_v1"

    static func increment(_ tags: [Tag], by delta: Int = 1) {
        guard delta > 0 else { return }
        for tag in tags {
            tag.usageCount += delta
        }
    }

    static func decrement(_ tags: [Tag], by delta: Int = 1) {
        guard delta > 0 else { return }
        for tag in tags {
            tag.usageCount = max(0, tag.usageCount - delta)
        }
    }

    /// 用于编辑 Memo 时的标签变化：新增标签 +1，移除标签 -1
    static func applyDelta(oldTags: [Tag], newTags: [Tag]) {
        let oldNames = Set(oldTags.map(\.name))
        let newNames = Set(newTags.map(\.name))

        for tag in newTags where !oldNames.contains(tag.name) {
            tag.usageCount += 1
        }
        for tag in oldTags where !newNames.contains(tag.name) {
            tag.usageCount = max(0, tag.usageCount - 1)
        }
    }

    /// 一次性回填旧数据的 usageCount；完成后写入标记避免重复执行
    static func backfillIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: backfillKey) == false else { return }

        let context = ModelContext(container)
        do {
            try resyncAll(in: context)
            defaults.set(true, forKey: backfillKey)
        } catch {
            // 回填失败时保留重试机会
            defaults.removeObject(forKey: backfillKey)
        }
    }

    static func resyncAll(in context: ModelContext) throws {
        let tags = try context.fetch(FetchDescriptor<Tag>())
        var hasChanges = false
        for tag in tags {
            let actual = tag.memos.count
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
