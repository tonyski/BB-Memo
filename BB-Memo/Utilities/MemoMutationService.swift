//
//  MemoMutationService.swift
//  BB-Memo
//

import Foundation
import SwiftData

/// 统一的写入入口：创建/更新/删除 Memo 与 Tag，并在保存前做标签计数校准。
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

        try saveWithBestEffortTagResync(context)
        return targetMemo
    }

    static func deleteMemo(_ memo: Memo, context: ModelContext) throws {
        memo.isDeleted = true
        memo.deletedAt = .now
        memo.updatedAt = .now
        memo.reminderDate = nil
        try saveWithBestEffortTagResync(context)
    }

    static func restoreMemo(_ memo: Memo, context: ModelContext) throws {
        memo.isDeleted = false
        memo.deletedAt = nil
        memo.updatedAt = .now
        try saveWithBestEffortTagResync(context)
    }

    static func permanentlyDeleteMemo(_ memo: Memo, context: ModelContext) throws {
        context.delete(memo)
        try saveWithBestEffortTagResync(context)
    }

    static func togglePinned(_ memo: Memo, context: ModelContext) throws {
        memo.isPinned.toggle()
        memo.updatedAt = .now
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func deleteTag(_ tag: Tag, context: ModelContext) throws {
        let tagID = tag.persistentModelID
        let relatedMemos = tag.memosList

        for memo in relatedMemos {
            memo.tags = memo.tagsList.filter { $0.persistentModelID != tagID }
        }

        context.delete(tag)
        try saveWithBestEffortTagResync(context)
    }

    private static func saveWithBestEffortTagResync(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        do {
            try TagUsageCounter.resyncAll(in: context)
        } catch {
            print("MemoMutationService tag resync failed: \(error)")
        }
    }

    private static func resolveTags(names: [String], in context: ModelContext) throws -> [Tag] {
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var existingByNormalized: [String: Tag] = [:]
        existingByNormalized.reserveCapacity(existingTags.count)

        for tag in existingTags {
            let key = tag.normalizedName.isEmpty ? Tag.normalize(tag.name).lowercased() : tag.normalizedName
            existingByNormalized[key] = tag
        }

        var resolved: [Tag] = []
        var seen = Set<String>()
        for rawName in names.sorted() {
            let displayName = Tag.normalize(rawName)
            guard !displayName.isEmpty else { continue }
            let normalized = displayName.lowercased()
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
