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
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTag: Tag?
    @State private var searchText = ""
    @State private var memoToEdit: Memo?
    @State private var selectedTimeFilter: MemoTimeFilter = .all
    @FocusState private var isFocused: Bool

    private var filteredMemos: [Memo] {
        // 未输入关键词时不展示内容
        guard !searchText.isEmpty else { return [] }

        var result = MemoFilter.apply(memos, searchText: searchText)

        // 时间筛选
        if let start = selectedTimeFilter.startDate {
            result = result.filter { $0.createdAt >= start }
        }

        return result
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
            if filteredMemos.isEmpty {
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
                        ForEach(filteredMemos) { memo in
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
        .onAppear { isFocused = true }
    }
}
