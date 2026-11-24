//
//  MemoMutationService.swift
//  BB-Memo
//

import Foundation
import SwiftData

/// 统一的写入入口：创建/更新/删除 Memo 与 Tag。
enum MemoMutationService {
    static func upsertMemo(
        memo: Memo?,
        content: String,
        reminderDate: Date?,
        selectedTagNames: Set<String>,
        context: ModelContext
    ) throws -> Memo {
        let tags = try resolveTags(names: Array(selectedTagNames), in: context)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let targetMemo: Memo
        if let memo {
            memo.content = trimmedContent
            memo.refreshContentHash()
            memo.updatedAt = .now
            memo.isDeleted = false
            memo.deletedAt = nil
            memo.reminderDate = reminderDate
            memo.tags = tags
            targetMemo = memo
        } else {
            let newMemo = Memo(content: trimmedContent, reminderDate: reminderDate, tags: tags)
            context.insert(newMemo)
            targetMemo = newMemo
        }

        try save(context)
        return targetMemo
    }

    static func deleteMemo(_ memo: Memo, context: ModelContext) throws {
        memo.isDeleted = true
        memo.deletedAt = .now
        memo.updatedAt = .now
        memo.reminderDate = nil
        try save(context)
    }

    /// - Parameter reminderDate: 非 nil 时一并恢复提醒（移入回收站会清空提醒），与恢复在同一次保存中完成。
    static func restoreMemo(
        _ memo: Memo,
        reminderDate: Date? = nil,
        context: ModelContext
    ) throws {
        memo.isDeleted = false
        memo.deletedAt = nil
        memo.updatedAt = .now
        if let reminderDate {
            memo.reminderDate = reminderDate
        }
        try save(context)
    }

    static func permanentlyDeleteMemo(_ memo: Memo, context: ModelContext) throws {
        context.delete(memo)
        try save(context)
    }

    static func togglePinned(_ memo: Memo, context: ModelContext) throws {
        memo.isPinned.toggle()
        memo.updatedAt = .now
        try save(context)
    }

    static func updateReminderDate(_ date: Date?, for memo: Memo, context: ModelContext) throws {
        memo.reminderDate = date
        memo.updatedAt = .now
        try save(context)
    }

    static func deleteTag(_ tag: Tag, context: ModelContext) throws {
        let tagID = tag.persistentModelID
        let relatedMemos = tag.memosList

        for memo in relatedMemos {
            memo.tags = memo.tagsList.filter { $0.persistentModelID != tagID }
        }

        context.delete(tag)
        try save(context)
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func resolveTags(names: [String], in context: ModelContext) throws -> [Tag] {
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var existingByNormalized: [String: Tag] = [:]
        existingByNormalized.reserveCapacity(existingTags.count)

        for tag in existingTags {
            existingByNormalized[tag.normalizedKey] = tag
        }

        var resolved: [Tag] = []
        var seen = Set<String>()
        for rawName in names.sorted() {
            let displayName = Tag.normalize(rawName)
            guard !displayName.isEmpty else { continue }
            let normalized = Tag.normalizedKey(for: displayName)
            guard seen.insert(normalized).inserted else { continue }

            if let existing = existingByNormalized[normalized] {
                resolved.append(existing)
            } else {
                let tag = Tag(name: displayName)
                context.insert(tag)
                existingByNormalized[normalized] = tag
                resolved.append(tag)
            }
        }
        return resolved
    }
}
