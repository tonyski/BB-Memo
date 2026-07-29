//
//  FlomoImporter.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation

struct FlomoMemo: Sendable {
    let content: String
    let createdAt: Date
}

enum FlomoImporter {
    nonisolated private static let divTokenRegex = try! NSRegularExpression(
        pattern: #"<div\b[^>]*>|</div\s*>"#,
        options: [.caseInsensitive]
    )

    nonisolated private static let memoOpeningRegex = makeOpeningTagRegex(className: "memo")
    nonisolated private static let timeOpeningRegex = makeOpeningTagRegex(className: "time")
    nonisolated private static let contentOpeningRegex = makeOpeningTagRegex(className: "content")

    /// 解析 flomo 导出的 HTML 内容
    nonisolated static func parse(html: String) -> [FlomoMemo] {
        var memos: [FlomoMemo] = []
        let nsString = html as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let memoOpenings = memoOpeningRegex.matches(
            in: html,
            range: fullRange
        )

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for opening in memoOpenings {
            guard let memoRange = matchingDivRange(in: html, openingRange: opening.range),
                  let memoHTMLRange = Range(memoRange, in: html) else { continue }
            let memoHTML = String(html[memoHTMLRange])
            guard let timeHTML = innerHTML(ofClass: "time", in: memoHTML),
                  let contentHTML = innerHTML(ofClass: "content", in: memoHTML) else { continue }

            let timeString = cleanHtml(timeHTML)
            if let date = dateFormatter.date(from: timeString) {
                let cleanContent = cleanHtml(contentHTML)
                guard !cleanContent.isEmpty else { continue }
                memos.append(FlomoMemo(content: cleanContent, createdAt: date))
            }
        }
        return memos
    }

    private nonisolated static func innerHTML(ofClass className: String, in html: String) -> String? {
        let fullRange = NSRange(html.startIndex..., in: html)
        let openingRegex = switch className {
        case "time": timeOpeningRegex
        case "content": contentOpeningRegex
        default: makeOpeningTagRegex(className: className)
        }
        guard let opening = openingRegex.firstMatch(
            in: html,
            range: fullRange
        ), let elementRange = matchingDivRange(in: html, openingRange: opening.range) else {
            return nil
        }
        let contentStart = opening.range.location + opening.range.length
        let contentLength = elementRange.location + elementRange.length
            - contentStart
            - closingTagLength(in: html, elementRange: elementRange)
        guard contentLength >= 0 else { return nil }
        return (html as NSString).substring(
            with: NSRange(location: contentStart, length: contentLength)
        )
    }

    private nonisolated static func makeOpeningTagRegex(className: String) -> NSRegularExpression {
        let escapedClassName = NSRegularExpression.escapedPattern(for: className)
        return try! NSRegularExpression(
            pattern: #"<div\b[^>]*class\s*=\s*["'][^"']*\b\#(escapedClassName)\b[^"']*["'][^>]*>"#,
            options: [.caseInsensitive]
        )
    }

    private nonisolated static func matchingDivRange(
        in html: String,
        openingRange: NSRange
    ) -> NSRange? {
        let nsString = html as NSString
        let searchStart = openingRange.location + openingRange.length
        guard searchStart <= nsString.length else { return nil }

        var depth = 1
        var cursor = searchStart
        while cursor < nsString.length {
            let searchRange = NSRange(location: cursor, length: nsString.length - cursor)
            guard let token = divTokenRegex.firstMatch(in: html, range: searchRange) else {
                return nil
            }
            let value = nsString.substring(with: token.range).lowercased()
            depth += value.hasPrefix("</") ? -1 : 1
            if depth == 0 {
                return NSRange(
                    location: openingRange.location,
                    length: token.range.location + token.range.length - openingRange.location
                )
            }
            cursor = token.range.location + token.range.length
        }
        return nil
    }

    private nonisolated static func closingTagLength(
        in html: String,
        elementRange: NSRange
    ) -> Int {
        let value = (html as NSString).substring(with: elementRange)
        guard let range = value.range(of: #"</div\s*>$"#, options: [.regularExpression, .caseInsensitive])
        else { return 0 }
        return value.distance(from: range.lowerBound, to: range.upperBound)
    }
    
    private nonisolated static func cleanHtml(_ html: String) -> String {
        var text = html
        
        // 1. 处理常见标签为换行或列表符
        text = text.replacingOccurrences(of: "<p>", with: "")
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        text = text.replacingOccurrences(of: "<li>", with: "- ")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        
        // 2. 移除所有剩余的 HTML 标签
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // 3. 处理 HTML 实体
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        
        // 4. 清理多余空行和首尾空格
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }
}
