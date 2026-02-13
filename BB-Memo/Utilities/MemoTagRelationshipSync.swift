//
//  MemoTagRelationshipSync.swift
//  BB
//
//  Created by Codex on 2026/2/13.
//

import Foundation
import SwiftData

/// 统一维护 Memo <-> Tag 双向关系，降低 CloudKit 关系变更漏同步风险。
enum MemoTagRelationshipSync {
    static func synchronizeTagBackReferences(for memo: Memo, oldTags: [Tag], newTags: [Tag]) {
        let memoKey = memoModelKey(memo)
        let oldByKey = uniqueTagsByModelKey(oldTags)
        let newByKey = uniqueTagsByModelKey(newTags)
        let oldKeys = Set(oldByKey.keys)
        let newKeys = Set(newByKey.keys)

        for key in oldKeys.subtracting(newKeys) {
            guard let tag = oldByKey[key] else { continue }
            var memos = tag.memosList
            memos.removeAll { memoModelKey($0) == memoKey }
            tag.memos = memos
        }

        for key in newKeys.subtracting(oldKeys) {
            guard let tag = newByKey[key] else { continue }
            if !tag.memosList.contains(where: { memoModelKey($0) == memoKey }) {
                var memos = tag.memosList
                memos.append(memo)
                tag.memos = memos
            }
        }
    }

    static func detachTagFromMemos(_ tag: Tag) {
        let tagKey = tagModelKey(tag)
        for memo in tag.memosList {
            var tags = memo.tagsList
            tags.removeAll { tagModelKey($0) == tagKey }
            memo.tags = tags
        }
        tag.memos = []
    }

    static func detachMemoFromTags(_ memo: Memo) {
        let memoKey = memoModelKey(memo)
        for tag in memo.tagsList {
            var memos = tag.memosList
            memos.removeAll { memoModelKey($0) == memoKey }
            tag.memos = memos
        }
        memo.tags = []
    }

    private static func tagModelKey(_ tag: Tag) -> String {
        String(describing: tag.persistentModelID)
    }

    private static func memoModelKey(_ memo: Memo) -> String {
        String(describing: memo.persistentModelID)
    }

    private static func uniqueTagsByModelKey(_ tags: [Tag]) -> [String: Tag] {
        var result: [String: Tag] = [:]
        result.reserveCapacity(tags.count)
        for tag in tags {
            let key = tagModelKey(tag)
            // 历史数据可能出现重复关系，这里取首个并跳过重复，避免 uniqueKeysWithValues 触发 trap。
            if result[key] == nil {
                result[key] = tag
            }
        }
        return result
    }
}
