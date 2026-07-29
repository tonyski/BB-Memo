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
            let previousTags = memo.tags ?? []
            let wasActive = !memo.isInRecycleBin
            memo.content = trimmedContent
            memo.refreshContentHash()
            memo.updatedAt = .now
            memo.isDeleted = false
            memo.deletedAt = nil
            memo.reminderDate = reminderDate
            memo.tags = tags
            updateUsageCounts(
                previousTags: previousTags,
                wasActive: wasActive,
                currentTags: tags,
                isActive: true
            )
            targetMemo = memo
        } else {
            let newMemo = Memo(content: trimmedContent, reminderDate: reminderDate, tags: tags)
            context.insert(newMemo)
            updateUsageCounts(
                previousTags: [],
                wasActive: false,
                currentTags: tags,
                isActive: true
            )
            targetMemo = newMemo
        }

        try save(context)
        return targetMemo
    }

    static func deleteMemo(_ memo: Memo, context: ModelContext) throws {
        let wasActive = !memo.isInRecycleBin
        memo.isDeleted = true
        memo.deletedAt = .now
        memo.updatedAt = .now
        memo.reminderDate = nil
        updateUsageCounts(
            previousTags: memo.tags ?? [],
            wasActive: wasActive,
            currentTags: memo.tags ?? [],
            isActive: false
        )
        try save(context)
    }

    static func restoreMemo(_ memo: Memo, context: ModelContext) throws {
        let wasActive = !memo.isInRecycleBin
        memo.isDeleted = false
        memo.deletedAt = nil
        memo.updatedAt = .now
        updateUsageCounts(
            previousTags: memo.tags ?? [],
            wasActive: wasActive,
            currentTags: memo.tags ?? [],
            isActive: true
        )
        try save(context)
    }

    static func permanentlyDeleteMemo(_ memo: Memo, context: ModelContext) throws {
        let tags = memo.tags ?? []
        let wasActive = !memo.isInRecycleBin
        context.delete(memo)
        updateUsageCounts(
            previousTags: tags,
            wasActive: wasActive,
            currentTags: [],
            isActive: false
        )
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

    /// 只更新本次关系变更涉及的标签，避免每次写入都扫描整个数据库。
    private static func updateUsageCounts(
        previousTags: [Tag],
        wasActive: Bool,
        currentTags: [Tag],
        isActive: Bool
    ) {
        let previous = previousTags.reduce(into: [ObjectIdentifier: Tag]()) {
            $0[ObjectIdentifier($1)] = $1
        }
        let current = currentTags.reduce(into: [ObjectIdentifier: Tag]()) {
            $0[ObjectIdentifier($1)] = $1
        }
        let identifiers = Set(previous.keys).union(current.keys)

        for identifier in identifiers {
            guard let tag = current[identifier] ?? previous[identifier] else { continue }
            let oldContribution = wasActive && previous[identifier] != nil ? 1 : 0
            let newContribution = isActive && current[identifier] != nil ? 1 : 0
            tag.usageCount = max(tag.usageCount + newContribution - oldContribution, 0)
        }
    }
}
