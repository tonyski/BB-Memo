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
    /// 正文里写着的 `#标签`：始终视为已选，不能在这里取消（需要改正文）。
    var lockedTagKeys: Set<String> = []
    var onAction: (TagSuggestion) -> Void

    private var selectedTagKeys: Set<String> {
        Set(
            selectedTagNames.compactMap { name in
                let normalized = Tag.normalize(name)
                return normalized.isEmpty ? nil : Tag.normalizedKey(for: normalized)
            }
        ).union(lockedTagKeys)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    let suggestionKey = Tag.normalizedKey(for: suggestion.name)
                    let isSelected = selectedTagKeys.contains(suggestionKey)
                    let isLocked = lockedTagKeys.contains(suggestionKey)
                    Button {
                        // 正文里的标签需要改正文才能去掉，这里点了不做处理。
                        guard !isLocked else { return }
                        onAction(suggestion)
                    } label: {
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
                    .accessibilityLabel("标签 \(suggestion.name)")
                    .accessibilityValue(isSelected ? "已选中" : "未选中")
                    .accessibilityHint(isLocked ? "正文中包含此标签" : "")
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.vertical, 10)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

struct TagPickerSheet: View {
    @Binding var selectedTagNames: Set<String>
    var onToggle: (String) -> Void
    var onCreate: (String) -> Void
    private let frequentTags: [Tag]

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private struct DisplayTag: Identifiable {
        let key: String
        let name: String

        var id: String { key }
    }

    init(
        allTags: [Tag],
        selectedTagNames: Binding<Set<String>>,
        onToggle: @escaping (String) -> Void,
        onCreate: @escaping (String) -> Void
    ) {
        self._selectedTagNames = selectedTagNames
        self.onToggle = onToggle
        self.onCreate = onCreate
        self.frequentTags = TagPickerSheet.makeFrequentTags(from: allTags)
    }

    private var normalizedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    private static func makeFrequentTags(from allTags: [Tag]) -> [Tag] {
        Tag.sortedByUsage(allTags)
            .prefix(12)
            .map { $0 }
    }

    private var selectedTagKeys: Set<String> {
        Set(
            selectedTagNames.compactMap { name in
                let normalized = Tag.normalize(name)
                return normalized.isEmpty ? nil : Tag.normalizedKey(for: normalized)
            }
        )
    }

    private var selectedTagsByKey: [String: String] {
        selectedTagNames.reduce(into: [String: String]()) { map, name in
            let normalized = Tag.normalize(name)
            guard !normalized.isEmpty else { return }
            let key = Tag.normalizedKey(for: normalized)
            if map[key] == nil {
                map[key] = normalized
            }
        }
    }

    private var displayTags: [DisplayTag] {
        var result: [DisplayTag] = []
        var seen = Set<String>()

        for tag in frequentTags {
            let normalized = Tag.normalize(tag.name)
            let key = Tag.normalizedKey(for: normalized)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                result.append(DisplayTag(key: key, name: tag.name))
            }
        }

        let extras = selectedTagsByKey
            .filter { !seen.contains($0.key) }
            .map { DisplayTag(key: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        result.append(contentsOf: extras)

        return result
    }

    private var inputFieldBackgroundColor: Color {
        Color.secondary.opacity(0.08)
    }

    private var isAddButtonDisabled: Bool {
        normalizedInput.isEmpty
    }

    private var addButtonBackgroundColor: Color {
        isAddButtonDisabled ? AppTheme.brandAccent.opacity(0.45) : AppTheme.brandAccent
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        TextField("输入标签名，例如：工作", text: $input)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit {
                                submitInputTag()
                            }
                            .font(.system(.body, design: AppTheme.Layout.fontDesign))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(inputFieldBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            submitInputTag()
                        } label: {
                            Text("添加")
                                .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                                .foregroundStyle(AppTheme.onBrandAccent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .frame(minWidth: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(addButtonBackgroundColor)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isAddButtonDisabled)
                        .opacity(isAddButtonDisabled ? 0.8 : 1)
                    }

                    if !displayTags.isEmpty {
                        Text("标签")
                            .font(.system(size: 12, weight: .medium, design: AppTheme.Layout.fontDesign))
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 72), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(displayTags) { tag in
                                let isSelected = selectedTagKeys.contains(tag.key)
                                Button {
                                    onToggle(tag.name)
                                } label: {
                                    Text("#\(tag.name)")
                                        .font(.system(size: 12, weight: .semibold, design: AppTheme.Layout.fontDesign))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
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
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .navigationTitle("添加标签")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - 编辑器共享逻辑

enum EditorHelper {
    static func toggleTag(_ name: String, selectedTagNames: inout Set<String>) {
        let normalized = Tag.normalize(name)
        guard !normalized.isEmpty else { return }
        let key = Tag.normalizedKey(for: normalized)

        let matchedNames = selectedTagNames.filter {
            Tag.normalizedKey(for: $0) == key
        }

        if matchedNames.isEmpty {
            selectedTagNames.insert(normalized)
        } else {
            for matched in matchedNames {
                selectedTagNames.remove(matched)
            }
        }
    }

}
