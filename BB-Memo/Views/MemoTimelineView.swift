//
//  MemoTimelineView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

/// BB 主页 — 时间线 + 标签侧栏
struct MemoTimelineView: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var allMemos: [Memo]

    @State private var memoToEdit: Memo?
    @Binding var showSidebar: Bool
    @State private var selectedTag: Tag?

    /// 过滤和排序后的 Memo
    private var filteredMemos: [Memo] {
        let filtered = selectedTag.map { tag in
            allMemos.filter { memo in
                memo.tags.contains { $0.persistentModelID == tag.persistentModelID }
            }
        } ?? allMemos
        
        return filtered.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        ZStack {
            // ── 主体内容 ──
            VStack(spacing: 0) {
                memoList
            }
            .background(AppTheme.background)
            .overlay(alignment: .leading) {
                // 左侧边缘滑动区域 (Moved here to be behind TopBar)
                Color.clear
                    .frame(width: 40)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.width > 80 && !showSidebar {
                                    withAnimation(AppTheme.spring) {
                                        showSidebar = true
                                    }
                                }
                            }
                    )
            }

            // ── 顶部栏 ──
            VStack(spacing: 0) {
                topBar
                    .background(.ultraThinMaterial)
                Divider().opacity(0.5)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            // ── 侧边栏 ──
            TagSidebarView(
                selectedTag: $selectedTag,
                isOpen: $showSidebar
            )
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .sheet(item: $memoToEdit) { memo in
            MemoEditorView(memo: memo)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(spacing: 4) {
            // 左侧菜单按钮
            Button {
                withAnimation(AppTheme.spring) {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.brandAccent)
            }
            .buttonStyle(.ghost)
            .padding(.leading, 8)

            Spacer()

            // 标题
            VStack(spacing: 2) {
                Text(selectedTag.map { "#\($0.name)" } ?? "BB Memo")
                    .font(.system(size: 17, weight: .semibold, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.primary)
                
                if selectedTag == nil {
                    Text("\(allMemos.count) 条记录")
                        .font(.system(size: 10, weight: .regular, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 搜索按钮
            NavigationLink {
                MemoSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.brandAccent)
        }
            .buttonStyle(.ghost)
            .padding(.trailing, 8)
        }
        .padding(.top, safeAreaInsets.top + 4)
        .padding(.bottom, 12)
    }

    @Environment(\.safeAreaInsets) private var safeAreaInsets

    // MARK: - Memo 列表

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Layout.cardSpacing) {
                // 顶部间距 (避让 TopBar)
                Spacer().frame(height: 60)

                if filteredMemos.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredMemos, id: \.persistentModelID) { memo in
                        MemoCardView(memo: memo, onEdit: {
                            memoToEdit = memo
                        })
                        .memoCardStyle()
                        .onTapGesture(count: 2) {
                            memoToEdit = memo
                        }
                    }
                }

                // 底部间距
                Spacer().frame(height: 120)
            }
            .padding(.horizontal, AppTheme.Layout.screenPadding)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.brandAccent.opacity(0.2))
            
            Text(selectedTag != nil ? "该标签下暂无内容" : "捕捉此刻的灵感")
                .font(.system(size: 15, weight: .medium, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
    }
}

