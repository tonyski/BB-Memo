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

    @State private var searchText = ""
    @State private var memoToEdit: Memo?
    @State private var selectedTimeFilter: TimeFilter = .all
    @FocusState private var isFocused: Bool

    // MARK: - 时间筛选枚举

    enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case today = "今天"
        case week = "近一周"
        case month = "近一月"
        case threeMonths = "近三月"

        var id: String { rawValue }

        var startDate: Date? {
            let cal = Calendar.current
            let now = Date.now
            switch self {
            case .all: return nil
            case .today: return cal.startOfDay(for: now)
            case .week: return cal.date(byAdding: .day, value: -7, to: now)
            case .month: return cal.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now)
            }
        }
    }

    private var filteredMemos: [Memo] {
        // 未输入关键词时不展示内容
        guard !searchText.isEmpty else { return [] }

        // 关键词搜索
        var result = memos.filter {
            $0.content.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

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
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        let isSelected = selectedTimeFilter == filter
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTimeFilter = filter
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: AppTheme.Layout.fontDesign))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? AppTheme.brandAccent : Color.secondary.opacity(0.1))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(Capsule())
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
            MemoEditorView(memo: memo)
        }
        .onAppear { isFocused = true }
    }
}
