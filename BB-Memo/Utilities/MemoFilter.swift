//
//  MemoFilter.swift
//  BB-Memo
//

import Foundation
import SwiftData

/// 统一的 Memo 过滤 + 置顶排序逻辑
enum MemoFilter {

    nonisolated static func sort(_ memos: [Memo]) -> [Memo] {
        memos.sorted { (lhs: Memo, rhs: Memo) in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return String(describing: lhs.persistentModelID) > String(describing: rhs.persistentModelID)
        }
    }

    nonisolated static func sortRecycleBin(_ memos: [Memo]) -> [Memo] {
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
        searchText: String = ""
    ) -> [Memo] {
        sort(
            memos.filter { memo in
                !memo.isInRecycleBin
                    && matchesTag(memo, tag: tag)
                    && matchesSearch(memo, searchText: searchText)
            }
        )
    }

    static func recycleBin(_ memos: [Memo], searchText: String = "") -> [Memo] {
        sortRecycleBin(
            memos.filter { memo in
                memo.isInRecycleBin && matchesSearch(memo, searchText: searchText)
            }
        )
    }

    private static func matchesTag(_ memo: Memo, tag: Tag?) -> Bool {
        guard let tag else { return true }
        return (memo.tags ?? []).contains { $0.persistentModelID == tag.persistentModelID }
    }

    private static func matchesSearch(_ memo: Memo, searchText: String) -> Bool {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return true }
        return memo.content.localizedCaseInsensitiveContains(keyword)
            || (memo.tags ?? []).contains { $0.name.localizedCaseInsensitiveContains(keyword) }
    }
}
