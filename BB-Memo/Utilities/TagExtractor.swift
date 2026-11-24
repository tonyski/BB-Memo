//
//  TagExtractor.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation
import NaturalLanguage

/// 标签提取工具：正则解析 #标签 + NaturalLanguage AI 关键词建议
enum TagExtractor {

    // 预编译正则，避免每次调用重新创建
    /// `#` 前不能紧跟 URL / 实体等符号（避免把 `a.com/x#section`、`&#123;` 当成标签），
    /// 标签名至少包含一个字母或汉字（避免 `第#1名` 这类纯数字）。
    nonisolated private static let hashtagRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_/&#.=?:])#([\p{L}\p{N}_]*\p{L}[\p{L}\p{N}_]*)"#
    )

    // MARK: - 正则提取 #标签

    /// 从文本中解析所有 `#标签` 名称（去重、保序）
    nonisolated static func extractHashtags(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = hashtagRegex.matches(in: text, range: range)
        var seen = Set<String>()
        return matches.compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: text) else { return nil }
            let tag = String(text[tagRange])
            return seen.insert(tag).inserted ? tag : nil
        }
    }

    // MARK: - AI 关键词提取

    /// 使用 NaturalLanguage 提取名词关键词作为标签建议
    nonisolated static func extractAITags(from text: String, limit: Int = 5) -> [String] {
        let cleanText = text.replacingOccurrences(
            of: #"#[\p{L}\p{N}_]+"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = cleanText

        var keywords: [String] = []
        var seen = Set<String>()

        tagger.enumerateTags(
            in: cleanText.startIndex..<cleanText.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { tag, tokenRange in
            if let tag, tag == .noun || tag == .organizationName || tag == .personalName || tag == .placeName {
                let word = String(cleanText[tokenRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if word.count >= 2, seen.insert(word).inserted {
                    keywords.append(word)
                }
            }
            return !Task.isCancelled && keywords.count < limit
        }

        return keywords
    }

    // MARK: - 综合建议

    /// 结合 AI 提取 + 已有标签匹配，返回建议标签列表 (用于 UI 展示)
    nonisolated static func suggestTags(
        from text: String,
        existingTagNames: [String]
    ) -> [TagSuggestion] {
        let aiKeywords = extractAITags(from: text, limit: 12)
        let currentHashtags = Set(
            extractHashtags(from: text).map { Tag.normalizedKey(for: $0) }
        )
        let existingByKey = existingTagNames.reduce(into: [String: String]()) { result, name in
            let key = Tag.normalizedKey(for: name)
            if result[key] == nil {
                result[key] = name
            }
        }
        
        var suggestions: [TagSuggestion] = []

        for keyword in aiKeywords {
            guard !Task.isCancelled else { break }
            let key = Tag.normalizedKey(for: keyword)
            guard !currentHashtags.contains(key) else { continue }
            let finalName = existingByKey[key] ?? keyword
            suggestions.append(TagSuggestion(name: finalName))
            if suggestions.count == 8 { break }
        }

        return suggestions
    }
}
