//
//  MemoEditorComponents.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

// MARK: - AI 标签建议栏

struct AISuggestionBar: View {
    let suggestions: [TagSuggestion]
    var onAction: (TagSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.brandAccent.opacity(0.8))
                ForEach(suggestions) { suggestion in
                    Button { onAction(suggestion) } label: {
                        HStack(spacing: 4) {
                            if suggestion.isAutoAdded && !suggestion.isExcluded {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            }
                            Text("#\(suggestion.name)")
                        }
                        .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            suggestion.isExcluded 
                            ? Color.secondary.opacity(0.1) 
                            : (suggestion.isAutoAdded ? AppTheme.brandAccent.opacity(0.15) : AppTheme.brandAccent.opacity(0.08))
                        )
                        .foregroundStyle(
                            suggestion.isExcluded 
                            ? Color.secondary 
                            : AppTheme.brandAccent
                        )
                        .clipShape(Capsule())
                        .strikethrough(suggestion.isExcluded)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.vertical, 10)
        }
        Divider().opacity(0.5)
    }
}

// MARK: - 提醒提示条

struct ReminderBanner: View {
    let date: Date
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.warning)
            Text(date, format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 11, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Layout.screenPadding)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        Divider()
    }
}

// MARK: - 底部编辑工具栏

struct EditorToolbar<Trailing: View>: View {
    var reminderDate: Date?
    var onHashtag: () -> Void
    var onReminder: () -> Void
    var trailing: Trailing

    init(
        reminderDate: Date? = nil,
        onHashtag: @escaping () -> Void,
        onReminder: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.reminderDate = reminderDate
        self.onHashtag = onHashtag
        self.onReminder = onReminder
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 28) {
            Button(action: onHashtag) {
                Image(systemName: "number")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.brandAccent.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Button(action: onReminder) {
                Image(systemName: reminderDate == nil ? "bell" : "bell.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(reminderDate == nil ? AppTheme.brandAccent.opacity(0.8) : AppTheme.warning)
            }
            .buttonStyle(.plain)
            
            Spacer()
            trailing
        }
        .padding(.horizontal, AppTheme.Layout.screenPadding + 4)
        .padding(.vertical, 14)
    }
}

// MARK: - 标签解析工具

enum MemoTagResolver {
    /// 从文本中解析标签名，匹配已有 Tag 或创建新 Tag
    static func resolveTags(
        from text: String, 
        allTags: [Tag], 
        suggestions: [TagSuggestion], 
        context: ModelContext
    ) -> [Tag] {
        // 1. 显式提取 # 标签
        let explicitNames = TagExtractor.extractHashtags(from: text)
        
        // 2. 自动发现建议标签 (仅包含未被排除的自动添加项)
        let autoNames = suggestions
            .filter { $0.isAutoAdded && !$0.isExcluded }
            .map { $0.name }
        
        // 3. 合并去重
        let combinedNames = Array(Set(explicitNames + autoNames))
        
        return combinedNames.map { name in
            if let existing = allTags.first(where: { $0.name == name }) {
                return existing
            }
            let tag = Tag(name: name)
            context.insert(tag)
            return tag
        }
    }
}

// MARK: - 编辑器共享逻辑

enum EditorHelper {
    /// 在文本末尾插入标签
    static func insertTag(_ suggestion: TagSuggestion, into content: inout String, suggestions: inout [TagSuggestion]) {
        let name = suggestion.name
        if !content.contains("#\(name)") {
            if !content.hasSuffix(" ") && !content.isEmpty { content += " " }
            content += "#\(name) "
        }
        suggestions.removeAll { $0.name == name }
    }

    /// 防抖触发 AI 标签分析
    static func triggerAIAnalysis(
        _ text: String,
        allTags: [Tag],
        debounceTask: inout Task<Void, Never>?,
        suggestions: Binding<[TagSuggestion]>
    ) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let names = allTags.map(\.name)
            let result = TagExtractor.suggestTags(from: text, existingTagNames: names)
            await MainActor.run { suggestions.wrappedValue = result }
        }
    }
}
