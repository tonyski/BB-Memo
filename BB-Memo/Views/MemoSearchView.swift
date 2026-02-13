//
//  MemoSearchView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

/// 搜索页面 — 支持关键词搜索 + 时间筛选
struct MemoSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTag: Tag?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchResults: [Memo] = []
    @State private var memoToEdit: Memo?
    @State private var selectedTimeFilter: MemoTimeFilter = .all
    @FocusState private var isFocused: Bool
    private var trimmedKeyword: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索输入框 — 圆角浮动样式
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("搜索 MEMO 或标签", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // 时间筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MemoTimeFilter.allCases, id: \.self) { filter in
                        let isSelected = selectedTimeFilter == filter
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTimeFilter = filter
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: AppTheme.Layout.fontDesign))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(isSelected ? Color.primary.opacity(0.15) : .clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // 结果
            if searchResults.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "magnifyingglass" : "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    Text(searchText.isEmpty ? "输入关键词搜索" : "未找到相关 MEMO")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchResults) { memo in
                            MemoCardView(memo: memo, onEdit: {
                                memoToEdit = memo
                            }, onTagTap: { tag in
                                withAnimation(AppTheme.spring) {
                                    selectedTag = tag
                                }
                                dismiss()
                            })
                            .memoCardStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("搜索")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $memoToEdit) { memo in
            MemoEditorSheetView(memo: memo)
        }
        .onAppear {
            isFocused = true
            debouncedSearchText = searchText
            performSearch()
        }
        .onChange(of: debouncedSearchText) { _, _ in
            performSearch()
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            performSearch()
        }
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                return
            }
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    debouncedSearchText = newValue
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private func performSearch() {
        guard !trimmedKeyword.isEmpty else {
            searchResults = []
            return
        }

        let startDate = selectedTimeFilter.startDate
        let contentMatches = fetchContentMatches(keyword: trimmedKeyword, startDate: startDate)
        let tagMatches = fetchTagMatches(keyword: trimmedKeyword, startDate: startDate)
        searchResults = MemoFilter.sort(merge(contentMatches, with: tagMatches))
    }

    private func fetchContentMatches(keyword: String, startDate: Date?) -> [Memo] {
        let descriptor = makeContentDescriptor(keyword: keyword, startDate: startDate)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchTagMatches(keyword: String, startDate: Date?) -> [Memo] {
        let tagDescriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { tag in
                tag.name.localizedStandardContains(keyword)
            }
        )
        let tags = (try? modelContext.fetch(tagDescriptor)) ?? []
        return tags.flatMap(\.memosList).filter { memo in
            guard let startDate else { return true }
            return memo.createdAt >= startDate
        }
    }

    private func makeContentDescriptor(keyword: String, startDate: Date?) -> FetchDescriptor<Memo> {
        if let startDate {
            return FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { memo in
                    memo.createdAt >= startDate
                    && memo.content.localizedStandardContains(keyword)
                },
                sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
            )
        }
        return FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { memo in
                memo.content.localizedStandardContains(keyword)
            },
            sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
        )
    }

    private func merge(_ lhs: [Memo], with rhs: [Memo]) -> [Memo] {
        var merged: [PersistentIdentifier: Memo] = [:]
        for memo in lhs {
            merged[memo.persistentModelID] = memo
        }
        for memo in rhs {
            merged[memo.persistentModelID] = memo
        }
        return Array(merged.values)
    }
}
