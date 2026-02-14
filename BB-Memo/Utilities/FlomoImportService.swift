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
                return "无法读取该文件，请重新选择。"
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
        var memoIdentityLookup = try makeMemoIdentityLookup(in: context)
        var importedCount = 0
        let importedAt = Date.now

        for flomoMemo in flomoMemos {
            let contentHash = Memo.computeContentHash(for: flomoMemo.content)
            let sourceIdentifier = makeFlomoSourceIdentifier(
                createdAt: flomoMemo.createdAt,
                contentHash: contentHash
            )
            let sourceIdentity = Memo.makeImportIdentity(
                sourceType: "flomo_html",
                sourceIdentifier: sourceIdentifier,
                contentHash: contentHash,
                content: flomoMemo.content,
                createdAt: flomoMemo.createdAt
            )
            let legacyIdentity = makeLegacyIdentity(
                contentHash: contentHash,
                content: flomoMemo.content,
                createdAt: flomoMemo.createdAt
            )
            guard !memoIdentityLookup.contains(sourceIdentity),
                  !memoIdentityLookup.contains(legacyIdentity) else { continue }
            memoIdentityLookup.insert(sourceIdentity)
            memoIdentityLookup.insert(legacyIdentity)

            let tagNames = TagExtractor.extractHashtags(from: flomoMemo.content)
            let tags = resolveTags(tagNames, tagLookup: &tagLookup, context: context)

            let newMemo = Memo(
                content: flomoMemo.content,
                createdAt: flomoMemo.createdAt,
                updatedAt: flomoMemo.createdAt,
                sourceType: "flomo_html",
                sourceIdentifier: sourceIdentifier,
                importedAt: importedAt,
                tags: tags
            )
            context.insert(newMemo)
            importedCount += 1
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        do {
            try TagUsageCounter.resyncAll(in: context)
        } catch {
            print("FlomoImportService tag resync failed: \(error)")
        }
        return Summary(importedCount: importedCount)
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

    private static func makeMemoIdentityLookup(in context: ModelContext) throws -> Set<String> {
        let existingMemos = try context.fetch(FetchDescriptor<Memo>())
        var lookup = Set<String>()
        lookup.reserveCapacity(existingMemos.count * 2)

        for memo in existingMemos {
            lookup.insert(memo.importIdentity)
            lookup.insert(
                makeLegacyIdentity(
                    contentHash: memo.contentHash,
                    content: memo.content,
                    createdAt: memo.createdAt
                )
            )
        }
        return lookup
    }

    private static func makeFlomoSourceIdentifier(createdAt: Date, contentHash: String) -> String {
        "\(Int(createdAt.timeIntervalSince1970))_\(contentHash)"
    }

    private static func makeLegacyIdentity(
        contentHash: String,
        content: String,
        createdAt: Date
    ) -> String {
        Memo.makeImportIdentity(
            sourceType: nil,
            sourceIdentifier: nil,
            contentHash: contentHash,
            content: content,
            createdAt: createdAt
        )
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
