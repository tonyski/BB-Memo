//
//  Tag.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation
import SwiftData

@Model
final class Tag: Identifiable {
    var name: String = ""
    var normalizedName: String = ""
    var createdAt: Date = Foundation.Date.now
    /// 已废弃：仅为兼容 CloudKit 中已有的字段而保留，不再读写。
    /// 它是派生数据，各设备在同步中途算出的值不同，写回后会互相覆盖、反复触发同步。
    /// 使用次数请用 `activeMemoCount` 在本地计算。
    var usageCount: Int = 0

    var memos: [Memo]?
    var memosList: [Memo] { memos ?? [] }
    /// 未进回收站的关联笔记数，只在本地计算，不持久化。
    var activeMemoCount: Int {
        memosList.reduce(0) { $1.isInRecycleBin ? $0 : $0 + 1 }
    }

    init(name: String, createdAt: Date = .now, memos: [Memo] = []) {
        let normalized = Tag.normalize(name)
        self.name = normalized
        self.normalizedName = normalized.lowercased()
        self.createdAt = createdAt
        self.memos = memos
    }

    nonisolated static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    nonisolated static func normalizedKey(for raw: String) -> String {
        normalize(raw).lowercased()
    }

    var normalizedKey: String {
        normalizedName.isEmpty ? Tag.normalizedKey(for: name) : normalizedName
    }

    static func stableDisplayOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.normalizedKey != rhs.normalizedKey { return lhs.normalizedKey < rhs.normalizedKey }
        return lhs.createdAt < rhs.createdAt
    }

    /// 本地计算每个标签的使用次数（每个标签只遍历一次关系）。
    static func usageCounts(for tags: [Tag]) -> [PersistentIdentifier: Int] {
        tags.reduce(into: [PersistentIdentifier: Int]()) {
            $0[$1.persistentModelID] = $1.activeMemoCount
        }
    }

    /// 按使用次数降序、名称升序排序。
    static func sortedByUsage(
        _ tags: [Tag],
        counts: [PersistentIdentifier: Int]? = nil
    ) -> [Tag] {
        let counts = counts ?? usageCounts(for: tags)
        return tags.sorted { lhs, rhs in
            let lhsCount = counts[lhs.persistentModelID, default: 0]
            let rhsCount = counts[rhs.persistentModelID, default: 0]
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }
}
