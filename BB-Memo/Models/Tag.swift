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

    var memos: [Memo]

    init(name: String, createdAt: Date = .now, memos: [Memo] = []) {
        self.name = name
        self.createdAt = createdAt
        self.memos = memos
    }
}
