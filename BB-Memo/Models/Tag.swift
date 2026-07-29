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
    /// 标签被多少条 Memo 使用（持久化计数，用于高性能排序/展示）
    var usageCount: Int = 0

    var memos: [Memo]?
    var memosList: [Memo] { memos ?? [] }

    init(name: String, createdAt: Date = .now, usageCount: Int = 0, memos: [Memo] = []) {
        let normalized = Tag.normalize(name)
        self.name = normalized
        self.normalizedName = normalized.lowercased()
        self.createdAt = createdAt
        self.usageCount = usageCount
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

    static func usageOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }
}
