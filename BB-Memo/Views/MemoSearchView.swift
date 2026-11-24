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
    @State private var searchTask: Task<Void, Never>?
    @State private var searchActor: MemoSearchActor?
    @State private var searchResults: [Memo] = []
    @State private var searchErrorMessage: String?
    @State private var memoToEdit: Memo?
    @State private var selectedTimeFilter: MemoTimeFilter = .all
    @FocusState private var isFocused: Bool
    private var visibleSearchResults: [Memo] {
        searchResults.filter { !$0.isInRecycleBin }
    }
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
                TextField("搜索笔记或标签", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索关键词")
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
            if visibleSearchResults.isEmpty {
                Spacer()
                if let searchErrorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.warning)
                        Text(searchErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            performSearch()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "magnifyingglass" : "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        Text(searchText.isEmpty ? "输入关键词开始搜索" : "没有找到相关笔记")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleSearchResults) { memo in
                            MemoCardView(memo: memo, onEdit: {
                                memoToEdit = memo
                            }, onTagTap: { tag in
                                withAnimation(AppTheme.spring) {
                                    selectedTag = tag
                                }
                                dismiss()
                            })
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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $memoToEdit) { memo in
            MemoEditorSheetView(memo: memo)
        }
        .onAppear {
            if searchActor == nil {
                searchActor = MemoSearchActor(modelContainer: modelContext.container)
            }
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
        .onReceive(AppNotifications.dataChanges) {
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
                debouncedSearchText = newValue
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            searchTask?.cancel()
        }
    }

    private func performSearch() {
        guard !trimmedKeyword.isEmpty else {
            searchTask?.cancel()
            searchResults = []
            searchErrorMessage = nil
            return
        }

        searchTask?.cancel()
        searchErrorMessage = nil
        let keyword = trimmedKeyword
        let startDate = selectedTimeFilter.startDate
        let actor = searchActor ?? MemoSearchActor(modelContainer: modelContext.container)
        searchActor = actor

        searchTask = Task {
            do {
                let stableIDs = try await actor.search(
                    keyword: keyword,
                    startDate: startDate,
                    limit: 120
                )
                guard !Task.isCancelled else { return }
                searchResults = try fetchMemos(stableIDs: stableIDs)
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchErrorMessage = "搜索失败，请重试。"
                print("MemoSearchView search failed: \(error)")
            }
        }
    }

    private func fetchMemos(stableIDs: [UUID]) throws -> [Memo] {
        guard !stableIDs.isEmpty else { return [] }
        let ids = stableIDs
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { ids.contains($0.stableID) }
        )
        let fetched = try modelContext.fetch(descriptor)
        let byID = fetched.reduce(into: [UUID: Memo]()) { result, memo in
            result[memo.stableID] = memo
        }
        return stableIDs.compactMap { byID[$0] }
    }
}

@ModelActor
private actor MemoSearchActor {
    func search(keyword: String, startDate: Date?, limit: Int) throws -> [UUID] {
        var contentDescriptor = makeContentDescriptor(keyword: keyword, startDate: startDate)
        contentDescriptor.fetchLimit = limit
        let contentMatches = try modelContext.fetch(contentDescriptor)
        try Task.checkCancellation()

        let tagDescriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.name.localizedStandardContains(keyword) }
        )
        let tags = try modelContext.fetch(tagDescriptor)
        var byID = contentMatches.reduce(into: [UUID: Memo]()) { result, memo in
            result[memo.stableID] = memo
        }
        for tag in tags {
            try Task.checkCancellation()
            for memo in tag.memosList where !memo.isInRecycleBin {
                if let startDate, memo.createdAt < startDate { continue }
                byID[memo.stableID] = memo
            }
        }
        try Task.checkCancellation()
        return MemoFilter.sort(Array(byID.values)).prefix(limit).map(\.stableID)
    }

    private func makeContentDescriptor(keyword: String, startDate: Date?) -> FetchDescriptor<Memo> {
        if let startDate {
            return FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> {
                    $0.createdAt >= startDate
                        && $0.deletedAt == nil
                        && $0.content.localizedStandardContains(keyword)
                },
                sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
            )
        }
        return FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> {
                $0.deletedAt == nil && $0.content.localizedStandardContains(keyword)
            },
            sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
        )
    }
}
