//
//  FlomoImporter.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation

struct FlomoMemo {
    let content: String
    let createdAt: Date
}

enum FlomoImporter {
    
    /// 解析 flomo 导出的 HTML 内容
    static func parse(html: String) -> [FlomoMemo] {
        var memos: [FlomoMemo] = []
        
        let memoPattern = #"<div class="memo">\s*<div class="time">(.*?)</div>\s*<div class="content">(.*?)</div>"#
        guard let memoRegex = try? NSRegularExpression(pattern: memoPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        
        let nsString = html as NSString
        let matches = memoRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        for match in matches {
            let timeRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            
            let timeStr = nsString.substring(with: timeRange)
            let contentHtml = nsString.substring(with: contentRange)
            
            if let date = dateFormatter.date(from: timeStr) {
                let cleanContent = cleanHtml(contentHtml)
                memos.append(FlomoMemo(content: cleanContent, createdAt: date))
            }
        }
        
        return memos
    }
    
    private static func cleanHtml(_ html: String) -> String {
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
