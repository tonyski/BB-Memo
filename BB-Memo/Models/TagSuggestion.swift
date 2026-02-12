//
//  TagSuggestion.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation

/// AI 标签建议模型
struct TagSuggestion: Identifiable, Equatable {
    var id: String { name }
    let name: String
    
    /// 是否由系统判定为“自动关联”
    let isAutoAdded: Bool
}
