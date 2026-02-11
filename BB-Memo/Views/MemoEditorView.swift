//
//  MemoEditorView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

/// 统一的 Memo 编辑器 — 支持新建和编辑已有内容
struct MemoEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTags: [Tag]

    /// 如果为 nil 则表示新建
    var memo: Memo?

    @State private var content = ""
    @State private var reminderDate: Date?
    @State private var showReminderPicker = false
    @State private var aiSuggestions: [TagSuggestion] = []
    @State private var debounceTask: Task<Void, Never>?

    @FocusState private var isFocused: Bool

    private var isEditing: Bool { memo != nil }
    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $content)
                        .font(.system(.body, design: AppTheme.Layout.fontDesign, weight: .regular))
                        .lineSpacing(6)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .onChange(of: content) { _, newValue in
                            EditorHelper.triggerAIAnalysis(newValue, allTags: allTags, debounceTask: &debounceTask, suggestions: $aiSuggestions)
                        }

                    if content.isEmpty {
                        Text("写下你的想法...")
                            .font(.system(.body, design: AppTheme.Layout.fontDesign))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, 12)

                Spacer()

                if !aiSuggestions.isEmpty {
                    AISuggestionBar(suggestions: aiSuggestions) { tag in
                        EditorHelper.insertTag(tag, into: &content, suggestions: &aiSuggestions)
                        HapticFeedback.light.play()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let date = reminderDate {
                    ReminderBanner(date: date) {
                        reminderDate = nil
                        HapticFeedback.medium.play()
                    }
                }

                EditorToolbar(
                    reminderDate: reminderDate,
                    onHashtag: {
                        if !content.isEmpty && !content.hasSuffix(" ") { content += " " }
                        content += "#"
                        HapticFeedback.light.play()
                    },
                    onReminder: {
                        showReminderPicker = true
                        HapticFeedback.light.play()
                    }
                ) {
                    if let memo = memo {
                        Text(memo.createdAt, style: .date)
                            .font(.system(size: 11, weight: .regular, design: AppTheme.Layout.fontDesign))
                            .foregroundStyle(.tertiary)
                    }
                }
                .background(Color.secondary.opacity(0.05))
            }
            .background(AppTheme.cardBackground)
            .navigationTitle(isEditing ? "编辑思考" : "新思考")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .font(.system(size: 15, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(trimmedContent.isEmpty ? .secondary : AppTheme.brandAccent)
                        .disabled(trimmedContent.isEmpty)
                }
            }
            .sheet(isPresented: $showReminderPicker) {
                ReminderPickerView(selectedDate: $reminderDate)
            }
            .onAppear {
                if let memo = memo {
                    content = memo.content
                    reminderDate = memo.reminderDate
                }
                // 延迟聚焦以确保动画流畅
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard !trimmedContent.isEmpty else { return }
        
        HapticFeedback.medium.play()

        let tags = MemoTagResolver.resolveTags(
            from: trimmedContent, 
            allTags: allTags, 
            suggestions: aiSuggestions,
            context: modelContext
        )
        let memoID: String

        if let memo = memo {
            // 更新已有
            memo.content = trimmedContent
            memo.updatedAt = .now
            memo.reminderDate = reminderDate
            memo.tags = tags
            memoID = memo.persistentModelID.hashValue.description
        } else {
            // 新建
            let newMemo = Memo(content: trimmedContent, reminderDate: reminderDate, tags: tags)
            modelContext.insert(newMemo)
            memoID = newMemo.persistentModelID.hashValue.description
        }

        // 通知管理
        NotificationManager.cancelReminder(memoID: memoID)
        if let date = reminderDate {
            NotificationManager.scheduleReminder(memoID: memoID, content: trimmedContent, at: date)
        }

        dismiss()
    }
}
