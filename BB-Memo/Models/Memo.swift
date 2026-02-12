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
    var content: String = ""
    var createdAt: Date = Foundation.Date.now
    var updatedAt: Date = Foundation.Date.now
    var isPinned: Bool = false
    var reminderDate: Date?

    @Relationship(inverse: \Tag.memos)
    var tags: [Tag]?
    
    /// 判断内容是否为长文本
    var isLong: Bool { content.count > 180 }
    var tagsList: [Tag] { tags ?? [] }
    /// 稳定提醒标识（避免使用 hashValue 导致重启后不一致）
    var reminderIdentifier: String { String(describing: persistentModelID) }

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
