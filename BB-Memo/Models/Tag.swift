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
    @Attribute(.unique)
    var name: String
    var createdAt: Date
    /// 标签被多少条 Memo 使用（持久化计数，用于高性能排序/展示）
    var usageCount: Int

    var memos: [Memo]

    init(name: String, createdAt: Date = .now, usageCount: Int = 0, memos: [Memo] = []) {
        self.name = name
        self.createdAt = createdAt
        self.usageCount = usageCount
        self.memos = memos
    }
}
