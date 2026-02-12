//
//  MemoEditorComponents.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

struct AISuggestionBar: View {
    let suggestions: [TagSuggestion]
    let selectedTagNames: Set<String>
    var onAction: (TagSuggestion) -> Void
    var onAddCustom: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onAddCustom) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.system(size: 12, weight: .semibold, design: AppTheme.Layout.fontDesign))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.brandAccent.opacity(0.12))
                    .foregroundStyle(AppTheme.brandAccent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(suggestions) { suggestion in
                    let isSelected = selectedTagNames.contains(suggestion.name)
                    Button { onAction(suggestion) } label: {
                        Text("#\(suggestion.name)")
                        .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                            ? AppTheme.brandAccent.opacity(0.15)
                            : Color.secondary.opacity(0.1)
                        )
                        .foregroundStyle(
                            isSelected ? AppTheme.brandAccent : Color.secondary
                        )
                        .clipShape(Capsule())
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

struct TagPickerSheet: View {
    let allTags: [Tag]
    let selectedTagNames: Set<String>
    var onToggle: (String) -> Void
    var onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private var normalizedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    private var frequentTags: [Tag] {
        allTags
            .sorted { lhs, rhs in
                let lCount = lhs.usageCount
                let rCount = rhs.usageCount
                if lCount != rCount { return lCount > rCount }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            .prefix(12)
            .map { $0 }
    }

    private var selectedNamesSorted: [String] {
        selectedTagNames.sorted()
    }

    private var inputFieldBackgroundColor: Color {
        #if os(macOS)
        return Color.secondary.opacity(0.12)
        #else
        return Color.secondary.opacity(0.08)
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        TextField("输入标签名，例如：工作", text: $input)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            #endif
                            .onSubmit {
                                submitInputTag()
                            }
                            .font(.system(.body, design: AppTheme.Layout.fontDesign))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(inputFieldBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            submitInputTag()
                        } label: {
                            Text("添加")
                                .font(.system(size: 14, weight: .semibold, design: AppTheme.Layout.fontDesign))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.brandAccent)
                        .disabled(normalizedInput.isEmpty)
                    }

                    if !selectedNamesSorted.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("已选标签")
                                .font(.system(size: 12, weight: .medium, design: AppTheme.Layout.fontDesign))
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(selectedNamesSorted, id: \.self) { name in
                                    Button {
                                        onToggle(name)
                                    } label: {
                                        Text("#\(name)")
                                            .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(AppTheme.brandAccent.opacity(0.15))
                                            .foregroundStyle(AppTheme.brandAccent)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if !frequentTags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("常用标签")
                                .font(.system(size: 12, weight: .medium, design: AppTheme.Layout.fontDesign))
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(frequentTags) { tag in
                                    let isSelected = selectedTagNames.contains(tag.name)
                                    Button {
                                        onToggle(tag.name)
                                    } label: {
                                        Text("#\(tag.name) \(tag.usageCount)")
                                            .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                isSelected
                                                ? AppTheme.brandAccent.opacity(0.15)
                                                : Color.secondary.opacity(0.1)
                                            )
                                            .foregroundStyle(
                                                isSelected ? AppTheme.brandAccent : Color.secondary
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("添加标签")
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 460)
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
    private func submitInputTag() {
        guard !normalizedInput.isEmpty else { return }
        onCreate(normalizedInput)
        input = ""
    }
}

// MARK: - 标签解析工具

enum MemoTagResolver {
    /// 根据选中的标签名，匹配已有 Tag 或创建新 Tag
    static func resolveTags(
        selectedNames: Set<String>,
        allTags: [Tag],
        context: ModelContext
    ) -> [Tag] {
        let sortedNames = selectedNames.sorted()
        return sortedNames.map { name in
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
    static func toggleTag(_ name: String, selectedTagNames: inout Set<String>) {
        if selectedTagNames.contains(name) {
            selectedTagNames.remove(name)
        } else {
            selectedTagNames.insert(name)
        }
    }

    static func triggerAIAnalysis(
        _ text: String,
        allTags: [Tag],
        debounceTask: inout Task<Void, Never>?,
        suggestions: Binding<[TagSuggestion]>,
        selectedTagNames: Binding<Set<String>>,
        autoSelectAISuggestions: Bool
    ) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let names = allTags.map(\.name)
            let result = TagExtractor.suggestTags(from: text, existingTagNames: names)
            await MainActor.run {
                var selected = selectedTagNames.wrappedValue
                if autoSelectAISuggestions && selected.isEmpty {
                    for suggestion in result where suggestion.isAutoAdded {
                        selected.insert(suggestion.name)
                    }
                }
                selectedTagNames.wrappedValue = selected
                suggestions.wrappedValue = result
            }
        }
    }
}
