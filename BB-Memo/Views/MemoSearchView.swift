//
//  MemoSearchView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import CoreData
import Combine

/// 搜索页面 — 支持关键词搜索 + 时间筛选
struct MemoSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTag: Tag?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchResults: [Memo] = []
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
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "magnifyingglass" : "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    Text(searchText.isEmpty ? "输入关键词开始搜索" : "没有找到相关笔记")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        .onReceive(NotificationCenter.default.publisher(for: .memoDataChanged).receive(on: RunLoop.main)) { _ in
            performSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
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
            searchTask?.cancel()
        }
    }

    private func performSearch() {
        guard !trimmedKeyword.isEmpty else {
            searchTask?.cancel()
            searchResults = []
            return
        }

        searchTask?.cancel()
        let keyword = trimmedKeyword
        let startDate = selectedTimeFilter.startDate
        let container = modelContext.container

        searchTask = Task(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let contentMatches = try context.fetch(Self.makeContentDescriptor(keyword: keyword, startDate: startDate))
                let tagDescriptor = FetchDescriptor<Tag>(
                    predicate: #Predicate<Tag> { tag in
                        tag.name.localizedStandardContains(keyword)
                    }
                )
                let tags = try context.fetch(tagDescriptor)
                let tagMatches = tags.flatMap(\.memosList).filter { memo in
                    guard !memo.isInRecycleBin else { return false }
                    guard let startDate else { return true }
                    return memo.createdAt >= startDate
                }
                let merged = MemoFilter.sort(Self.merge(contentMatches, with: tagMatches))
                let resultStableIDs = Array(merged.prefix(120)).map(\.stableID)

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = fetchMemosByStableIDs(resultStableIDs)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = []
                }
            }
        }
    }

    private static func makeContentDescriptor(keyword: String, startDate: Date?) -> FetchDescriptor<Memo> {
        if let startDate {
            return FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { memo in
                    memo.createdAt >= startDate
                    && memo.deletedAt == nil
                    && memo.content.localizedStandardContains(keyword)
                },
                sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
            )
        }
        return FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { memo in
                memo.deletedAt == nil
                && memo.content.localizedStandardContains(keyword)
            },
            sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
        )
    }

    private static func merge(_ lhs: [Memo], with rhs: [Memo]) -> [Memo] {
        var merged: [UUID: Memo] = [:]
        for memo in lhs {
            merged[memo.stableID] = memo
        }
        for memo in rhs {
            merged[memo.stableID] = memo
        }
        return Array(merged.values)
    }

    private func fetchMemosByStableIDs(_ stableIDs: [UUID]) -> [Memo] {
        guard !stableIDs.isEmpty else { return [] }
        let ids = stableIDs
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { memo in
                ids.contains(memo.stableID)
            }
        )
        let memos = ((try? modelContext.fetch(descriptor)) ?? []).filter { !$0.isInRecycleBin }
        let byID = Dictionary(uniqueKeysWithValues: memos.map { ($0.stableID, $0) })
        var ordered: [Memo] = []
        ordered.reserveCapacity(stableIDs.count)
        for id in stableIDs {
            if let memo = byID[id] {
                ordered.append(memo)
            }
        }
        return ordered
    }
}
