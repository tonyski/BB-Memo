//
//  MemoFilter.swift
//  BB-Memo
//

import Foundation
import SwiftData

/// 统一的 Memo 过滤 + 置顶排序逻辑
enum MemoFilter {

    static func sort(_ memos: [Memo]) -> [Memo] {
        memos.sorted { (lhs: Memo, rhs: Memo) in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return String(describing: lhs.persistentModelID) > String(describing: rhs.persistentModelID)
        }
    }

    static func sortRecycleBin(_ memos: [Memo]) -> [Memo] {
        memos.sorted { (lhs: Memo, rhs: Memo) in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return String(describing: lhs.persistentModelID) > String(describing: rhs.persistentModelID)
        }
    }

    /// 按标签过滤、关键词搜索，并按 置顶 > 创建时间 排序
    static func apply(
        _ memos: [Memo],
        tag: Tag? = nil,
        searchText: String = "",
        includeDeleted: Bool = false
    ) -> [Memo] {
        sort(
            memos.filter { memo in
                if !includeDeleted && memo.isInRecycleBin { return false }
                return matchesTag(memo, tag: tag) && matchesSearch(memo, searchText: searchText)
            }
        )
    }

    private static func matchesTag(_ memo: Memo, tag: Tag?) -> Bool {
        guard let tag else { return true }
        return memo.tagsList.contains { $0.persistentModelID == tag.persistentModelID }
    }

    private static func matchesSearch(_ memo: Memo, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return memo.content.localizedCaseInsensitiveContains(searchText)
            || memo.tagsList.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
