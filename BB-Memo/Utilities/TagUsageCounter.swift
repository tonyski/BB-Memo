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
    /// 重新校准 `usageCount` 与 `normalizedName`，并统一保存当前上下文中的改动。
    static func resyncAll(in context: ModelContext) throws {
        let tags = try context.fetch(FetchDescriptor<Tag>())
        for tag in tags {
            let normalized = Tag.normalize(tag.name).lowercased()
            if tag.normalizedName != normalized {
                tag.normalizedName = normalized
            }
            let actual = tag.memosList.count(where: { !$0.isInRecycleBin })
            if tag.usageCount != actual {
                tag.usageCount = actual
            }
        }
        try context.save()
    }
}
