//
//  TagSuggestion.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation

/// AI 标签建议模型
struct TagSuggestion: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
}
