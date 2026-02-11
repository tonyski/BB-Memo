//
//  MemoFilter.swift
//  BB-Memo
//

import Foundation
import SwiftData

/// 统一的 Memo 过滤 + 置顶排序逻辑
enum MemoFilter {

    /// 按标签过滤、关键词搜索，并按 置顶 > 创建时间 排序
    static func apply(
        _ memos: [Memo],
        tag: Tag? = nil,
        searchText: String = ""
    ) -> [Memo] {
        memos
            .filter { memo in
                let matchesTag = tag == nil
                    || memo.tags.contains { $0.persistentModelID == tag?.persistentModelID }
                let matchesSearch = searchText.isEmpty
                    || memo.content.localizedCaseInsensitiveContains(searchText)
                    || memo.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
                return matchesTag && matchesSearch
            }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.createdAt > b.createdAt
            }
    }
}
