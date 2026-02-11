//
//  Memo.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation
import SwiftData

@Model
final class Memo {
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var reminderDate: Date?

    @Relationship(inverse: \Tag.memos)
    var tags: [Tag]
    
    /// 判断内容是否为长文本
    var isLong: Bool { content.count > 180 }

    init(
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false,
        reminderDate: Date? = nil,
        tags: [Tag] = []
    ) {
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.reminderDate = reminderDate
        self.tags = tags
    }
}
