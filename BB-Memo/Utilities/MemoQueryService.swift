//
//  MemoQueryService.swift
//  BB-Memo
//

import Foundation
import SwiftData

struct MemoPageCursor {
    var pinnedOffset = 0
    var regularOffset = 0
    var recycleBinOffset = 0
    var hasMorePinned = true

    var activeLoadedCount: Int { pinnedOffset + regularOffset }
}

enum MemoQueryService {
    static func activeCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(
            FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { $0.deletedAt == nil }
            )
        )
    }

    static func recycleBinCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(
            FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { $0.deletedAt != nil }
            )
        )
    }

    static func fetchActivePage(
        in context: ModelContext,
        cursor: inout MemoPageCursor,
        limit: Int
    ) throws -> [Memo] {
        var page: [Memo] = []
        var remaining = limit

        if cursor.hasMorePinned {
            let requestedCount = remaining
            var descriptor = FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> {
                    $0.isPinned && $0.deletedAt == nil
                },
                sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
            )
            descriptor.fetchOffset = cursor.pinnedOffset
            descriptor.fetchLimit = requestedCount
            let pinned = try context.fetch(descriptor)
            page.append(contentsOf: pinned)
            cursor.pinnedOffset += pinned.count
            remaining -= pinned.count
            cursor.hasMorePinned = pinned.count == requestedCount
        }

        if remaining > 0 {
            var descriptor = FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> {
                    !$0.isPinned && $0.deletedAt == nil
                },
                sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
            )
            descriptor.fetchOffset = cursor.regularOffset
            descriptor.fetchLimit = remaining
            let regular = try context.fetch(descriptor)
            page.append(contentsOf: regular)
            cursor.regularOffset += regular.count
        }
        return page
    }

    static func fetchRecycleBinPage(
        in context: ModelContext,
        cursor: inout MemoPageCursor,
        limit: Int
    ) throws -> [Memo] {
        var descriptor = recycleBinDescriptor
        descriptor.fetchOffset = cursor.recycleBinOffset
        descriptor.fetchLimit = limit
        let page = try context.fetch(descriptor)
        cursor.recycleBinOffset += page.count
        return page
    }

    static func fetchAll(
        in context: ModelContext,
        recycleBin: Bool
    ) throws -> [Memo] {
        try context.fetch(
            recycleBin
                ? recycleBinDescriptor
                : FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.deletedAt == nil },
                    sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                )
        )
    }

    private static var recycleBinDescriptor: FetchDescriptor<Memo> {
        FetchDescriptor(
            predicate: #Predicate<Memo> { $0.deletedAt != nil },
            sortBy: [
                SortDescriptor(\Memo.updatedAt, order: .reverse),
                SortDescriptor(\Memo.createdAt, order: .reverse)
            ]
        )
    }
}
