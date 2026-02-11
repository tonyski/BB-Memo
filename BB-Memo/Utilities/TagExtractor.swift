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
    private static let hashtagRegex = try! NSRegularExpression(pattern: #"#([\p{L}\p{N}_]+)"#)

    // MARK: - 正则提取 #标签

    /// 从文本中解析所有 `#标签` 名称（去重、保序）
    static func extractHashtags(from text: String) -> [String] {
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
    static func extractAITags(from text: String, limit: Int = 5) -> [String] {
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
            return keywords.count < limit
        }

        return keywords
    }

    // MARK: - 综合建议

    /// 判断一个关键词是否符合“自动标签”的标准
    private static func isAutoTag(keyword: String, text: String, existingNamesLowercased: Set<String>) -> Bool {
        // 已有的标签，高频词，自动关联
        guard !existingNamesLowercased.contains(keyword.lowercased()) else { return true }
        // 新词：仅在文本较长时自动关联（比较保守）
        return text.count > 50
    }

    /// 结合 AI 提取 + 已有标签匹配，返回建议标签列表 (用于 UI 展示)
    static func suggestTags(from text: String, existingTagNames: [String]) -> [TagSuggestion] {
        let aiKeywords = extractAITags(from: text, limit: 12)
        let currentHashtags = Set(extractHashtags(from: text).map { $0.lowercased() })
        let existingLowercased = Set(existingTagNames.map { $0.lowercased() })
        
        var suggestions: [TagSuggestion] = []
        var autoAddedCount = 0

        for keyword in aiKeywords where !currentHashtags.contains(keyword.lowercased()) {
            let isAuto = isAutoTag(keyword: keyword, text: text, existingNamesLowercased: existingLowercased)
            
            // 限制自动添加的数量上限为 3
            let autoAdded = isAuto && autoAddedCount < 3
            if autoAdded { autoAddedCount += 1 }

            // 寻找原始名称（处理大小写）
            let finalName = existingTagNames.first(where: { $0.lowercased() == keyword.lowercased() }) ?? keyword
            
            suggestions.append(TagSuggestion(name: finalName, isAutoAdded: autoAdded))
        }

        return Array(suggestions.prefix(8))
    }

    // MARK: - 自动关联逻辑

    /// 自动发现并关联标签（用于保存时自动生成）
    static func autoDiscoverTags(from text: String, existingTagNames: [String]) -> [String] {
        let suggestions = suggestTags(from: text, existingTagNames: existingTagNames)
        return suggestions.filter { $0.isAutoAdded }.map { $0.name }
    }
}
