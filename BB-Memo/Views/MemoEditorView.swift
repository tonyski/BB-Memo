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
    @State private var aiSuggestions: [TagSuggestion] = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedTagNames: Set<String> = []
    @State private var activeSheet: ActiveSheet?
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var allTagNamesSnapshot: [String] = []

    @FocusState private var isFocused: Bool

    private var isEditing: Bool { memo != nil }
    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var reminderButtonTitle: String {
        let value = reminderDate?.formatted(.dateTime.month().day().hour().minute()) ?? "未设置"
        return "设置提醒 · \(value)"
    }
    private var reminderIconName: String {
        reminderDate == nil ? "bell.badge" : "bell.fill"
    }
    private var reminderIconColor: Color {
        reminderDate == nil ? AppTheme.brandAccent : AppTheme.warning
    }
    private enum ActiveSheet: Identifiable {
        case reminder
        case tagPicker

        var id: Int {
            switch self {
            case .reminder: 0
            case .tagPicker: 1
            }
        }
    }
    private var mergedTagSuggestions: [TagSuggestion] {
        var result = aiSuggestions
        let existingLower = Set(aiSuggestions.map { $0.name.lowercased() })
        let extras = selectedTagNames
            .filter { !existingLower.contains($0.lowercased()) }
            .sorted()
            .map { TagSuggestion(name: $0, isAutoAdded: false) }
        result.append(contentsOf: extras)
        return result
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
                            EditorHelper.triggerAIAnalysis(
                                newValue,
                                existingTagNames: allTagNamesSnapshot,
                                debounceTask: &debounceTask,
                                suggestions: $aiSuggestions
                            )
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.cardBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomAccessoryArea
            }
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .reminder:
                    ReminderPickerView(selectedDate: $reminderDate)
                case .tagPicker:
                    TagPickerSheet(
                        allTags: allTags,
                        selectedTagNames: $selectedTagNames,
                        onToggle: { name in
                            toggleTagByName(name)
                        },
                        onCreate: { name in
                            addCustomTag(named: name)
                        }
                    )
                    #if os(iOS)
                    .presentationDetents([.height(360)])
                    #endif
                }
            }
            .alert("保存失败", isPresented: $showSaveErrorAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .onAppear {
                allTagNamesSnapshot = allTags.map(\.name)
                if let memo = memo {
                    content = memo.content
                    reminderDate = memo.reminderDate
                    selectedTagNames = Set(memo.tagsList.map(\.name))
                }
                // 延迟聚焦以确保动画流畅
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
            .onChange(of: allTags.map(\.name)) { _, newValue in
                allTagNamesSnapshot = newValue
            }
        }
    }

    private var bottomAccessoryArea: some View {
        VStack(spacing: 0) {
            if !mergedTagSuggestions.isEmpty {
                AISuggestionBar(
                    suggestions: mergedTagSuggestions,
                    selectedTagNames: selectedTagNames
                ) { tag in
                    toggleTagByName(tag.name)
                    HapticFeedback.light.play()
                } onAddCustom: {
                    activeSheet = .tagPicker
                }
                .animation(nil, value: selectedTagNames)
            }

            reminderButton
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, mergedTagSuggestions.isEmpty ? 8 : 10)
                .padding(.bottom, 10)
        }
        .background(AppTheme.cardBackground)
    }

    // MARK: - Actions

    private func save() {
        guard !trimmedContent.isEmpty else { return }
        
        HapticFeedback.medium.play()

        let tags = MemoTagResolver.resolveTags(
            selectedNames: selectedTagNames,
            allTags: allTags,
            context: modelContext
        )
        let targetMemo: Memo

        if let memo = memo {
            // 更新已有
            let oldTags = memo.tagsList
            memo.content = trimmedContent
            memo.refreshContentHash()
            memo.updatedAt = .now
            memo.reminderDate = reminderDate
            memo.tags = tags
            MemoTagRelationshipSync.synchronizeTagBackReferences(for: memo, oldTags: oldTags, newTags: tags)
            TagUsageCounter.applyDelta(oldTags: oldTags, newTags: tags)
            targetMemo = memo
        } else {
            // 新建
            let newMemo = Memo(content: trimmedContent, reminderDate: reminderDate, tags: tags)
            modelContext.insert(newMemo)
            MemoTagRelationshipSync.synchronizeTagBackReferences(for: newMemo, oldTags: [], newTags: tags)
            TagUsageCounter.increment(tags)
            targetMemo = newMemo
        }

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
            return
        }
        let memoID = targetMemo.reminderIdentifier

        // 通知管理
        NotificationManager.cancelReminder(memoID: memoID)
        if let date = reminderDate {
            NotificationManager.scheduleReminder(memoID: memoID, content: trimmedContent, at: date)
        }

        AppNotifications.postMemoDataChanged()
        dismiss()
    }

    private func addCustomTag(named raw: String) {
        let canonicalName = canonicalTagName(for: raw)
        guard !canonicalName.isEmpty else { return }
        selectedTagNames.insert(canonicalName)
        if aiSuggestions.firstIndex(where: { $0.name.caseInsensitiveCompare(canonicalName) == .orderedSame }) == nil {
            aiSuggestions.insert(TagSuggestion(name: canonicalName, isAutoAdded: false), at: 0)
        }
    }

    private func toggleTagByName(_ raw: String) {
        let canonicalName = canonicalTagName(for: raw)
        guard !canonicalName.isEmpty else { return }
        EditorHelper.toggleTag(canonicalName, selectedTagNames: &selectedTagNames)
    }

    private func canonicalTagName(for raw: String) -> String {
        let normalized = Tag.normalize(raw)
        guard !normalized.isEmpty else { return "" }
        let key = normalized.lowercased()
        return allTags.first {
            let existingKey = $0.normalizedName.isEmpty ? Tag.normalize($0.name).lowercased() : $0.normalizedName
            return existingKey == key
        }?.name ?? normalized
    }

    private var reminderButton: some View {
        Button {
            activeSheet = .reminder
            HapticFeedback.light.play()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: reminderIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reminderIconColor)
                Text(reminderButtonTitle)
                    .font(.system(size: 14, weight: .regular, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
