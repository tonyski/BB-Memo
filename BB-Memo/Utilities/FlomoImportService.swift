//
//  FlomoImportService.swift
//  BB-Memo
//

import Foundation
import SwiftData

enum FlomoImportService {
    struct Summary {
        let importedCount: Int
    }

    enum ImportError: LocalizedError {
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "无法获取文件访问权限"
            }
        }
    }

    static func importFromFile(at url: URL, context: ModelContext) async throws -> Summary {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.permissionDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let html = try await Task.detached(priority: .userInitiated) {
            try String(contentsOf: url, encoding: .utf8)
        }.value
        let flomoMemos = await Task.detached(priority: .userInitiated) {
            FlomoImporter.parse(html: html)
        }.value

        var tagLookup = try makeTagLookup(in: context)

        for flomoMemo in flomoMemos {
            let tagNames = TagExtractor.extractHashtags(from: flomoMemo.content)
            let tags = resolveTags(tagNames, tagLookup: &tagLookup, context: context)

            context.insert(
                Memo(
                    content: flomoMemo.content,
                    createdAt: flomoMemo.createdAt,
                    updatedAt: flomoMemo.createdAt,
                    tags: tags
                )
            )
            TagUsageCounter.increment(tags)
        }

        try context.save()
        return Summary(importedCount: flomoMemos.count)
    }

    private static func makeTagLookup(in context: ModelContext) throws -> [String: Tag] {
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var lookup: [String: Tag] = [:]
        for tag in existingTags {
            let key = tag.normalizedName.isEmpty ? Tag.normalize(tag.name).lowercased() : tag.normalizedName
            lookup[key] = tag
        }
        return lookup
    }

    private static func resolveTags(
        _ names: [String],
        tagLookup: inout [String: Tag],
        context: ModelContext
    ) -> [Tag] {
        var results: [Tag] = []
        var seen = Set<String>()

        for name in names {
            let normalizedName = Tag.normalize(name)
            guard !normalizedName.isEmpty else { continue }
            let key = normalizedName.lowercased()
            guard seen.insert(key).inserted else { continue }

            if let existing = tagLookup[key] {
                results.append(existing)
            } else {
                let newTag = Tag(name: normalizedName)
                context.insert(newTag)
                tagLookup[key] = newTag
                results.append(newTag)
            }
        }
        return results
    }
}
