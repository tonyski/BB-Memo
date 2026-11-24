//
//  FlomoImportService.swift
//  BB-Memo
//

import Foundation
import SwiftData

enum FlomoImportService {
    struct Summary: Sendable {
        let parsedCount: Int
        let importedCount: Int
        let duplicateCount: Int
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

    static func importFromFile(at url: URL, modelContainer: ModelContainer) async throws -> Summary {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.permissionDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let flomoMemos = try await Task.detached(priority: .userInitiated) {
            let html = try String(contentsOf: url, encoding: .utf8)
            return FlomoImporter.parse(html: html)
        }.value
        let importer = FlomoImportActor(modelContainer: modelContainer)
        return try await importer.importMemos(flomoMemos)
    }
}

@ModelActor
private actor FlomoImportActor {
    func importMemos(_ flomoMemos: [FlomoMemo]) throws -> FlomoImportService.Summary {
        var tagLookup = try makeTagLookup()
        var memoIdentityLookup = try makeMemoIdentityLookup()
        var importedCount = 0
        var duplicateCount = 0
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
                content: flomoMemo.content,
                createdAt: flomoMemo.createdAt
            )
            let legacyIdentity = makeLegacyIdentity(
                content: flomoMemo.content,
                createdAt: flomoMemo.createdAt
            )
            guard !memoIdentityLookup.contains(sourceIdentity),
                  !memoIdentityLookup.contains(legacyIdentity) else {
                duplicateCount += 1
                continue
            }
            memoIdentityLookup.insert(sourceIdentity)
            memoIdentityLookup.insert(legacyIdentity)

            let tagNames = TagExtractor.extractHashtags(from: flomoMemo.content)
            let tags = resolveTags(tagNames, tagLookup: &tagLookup)

            let newMemo = Memo(
                content: flomoMemo.content,
                createdAt: flomoMemo.createdAt,
                updatedAt: flomoMemo.createdAt,
                sourceType: "flomo_html",
                sourceIdentifier: sourceIdentifier,
                importedAt: importedAt,
                tags: tags
            )
            modelContext.insert(newMemo)
            importedCount += 1
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return FlomoImportService.Summary(
            parsedCount: flomoMemos.count,
            importedCount: importedCount,
            duplicateCount: duplicateCount
        )
    }

    private func makeTagLookup() throws -> [String: Tag] {
        let existingTags = try modelContext.fetch(FetchDescriptor<Tag>())
        var lookup: [String: Tag] = [:]
        for tag in existingTags {
            lookup[tag.normalizedKey] = tag
        }
        return lookup
    }

    private func makeMemoIdentityLookup() throws -> Set<String> {
        let existingMemos = try modelContext.fetch(FetchDescriptor<Memo>())
        var lookup = Set<String>()
        lookup.reserveCapacity(existingMemos.count * 2)

        for memo in existingMemos {
            lookup.insert(memo.importIdentity)
            lookup.insert(
                makeLegacyIdentity(
                    content: memo.content,
                    createdAt: memo.createdAt
                )
            )
        }
        return lookup
    }

    private func makeFlomoSourceIdentifier(createdAt: Date, contentHash: String) -> String {
        "\(Int(createdAt.timeIntervalSince1970))_\(contentHash)"
    }

    private func makeLegacyIdentity(
        content: String,
        createdAt: Date
    ) -> String {
        Memo.makeImportIdentity(
            sourceType: nil,
            sourceIdentifier: nil,
            content: content,
            createdAt: createdAt
        )
    }

    private func resolveTags(
        _ names: [String],
        tagLookup: inout [String: Tag]
    ) -> [Tag] {
        var results: [Tag] = []
        var seen = Set<String>()

        for name in names {
            let normalizedName = Tag.normalize(name)
            guard !normalizedName.isEmpty else { continue }
            let key = Tag.normalizedKey(for: normalizedName)
            guard seen.insert(key).inserted else { continue }

            if let existing = tagLookup[key] {
                results.append(existing)
            } else {
                let newTag = Tag(name: normalizedName)
                modelContext.insert(newTag)
                tagLookup[key] = newTag
                results.append(newTag)
            }
        }
        return results
    }
}
