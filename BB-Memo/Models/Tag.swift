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

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }
}
