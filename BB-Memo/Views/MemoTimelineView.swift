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
    @Environment(\.modelContext) private var modelContext

    @State private var memoToEdit: Memo?
    @Binding var showSidebar: Bool
    @State private var selectedTag: Tag?
    @State private var displayedMemos: [Memo] = []
    @State private var loadedCount = 0
    @State private var pinnedLoadedCount = 0
    @State private var unpinnedLoadedCount = 0
    @State private var pinnedExhausted = false
    @State private var canLoadMore = true
    @State private var isLoadingPage = false
    @State private var totalMemoCount = 0

    private let pageSize = 40

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
        .sheet(item: $memoToEdit, onDismiss: resetAndReload) { memo in
            MemoEditorView(memo: memo)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if displayedMemos.isEmpty {
                resetAndReload()
            }
        }
        .onChange(of: selectedTag?.persistentModelID) { _, _ in
            resetAndReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoDataChanged)) { _ in
            resetAndReload()
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
                HStack(spacing: 4) {
                    Text(selectedTag.map { "#\($0.name)" } ?? "BB Memo")
                        .font(.system(size: 17, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(.primary)
                    
                    if selectedTag != nil {
                        Button {
                            withAnimation(AppTheme.spring) {
                                selectedTag = nil
                            }
                            HapticFeedback.light.play()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if selectedTag == nil {
                    Text("\(totalMemoCount) 条记录")
                        .font(.system(size: 10, weight: .regular, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 搜索按钮
            NavigationLink {
                MemoSearchView(selectedTag: $selectedTag)
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
                // 顶部间距（动态避让 TopBar）
                Spacer().frame(height: 60)

                if displayedMemos.isEmpty && !isLoadingPage {
                    emptyState
                } else {
                    ForEach(displayedMemos, id: \.persistentModelID) { memo in
                        MemoCardView(memo: memo, onEdit: {
                            memoToEdit = memo
                        }, onTagTap: { tag in
                            selectedTag = tag
                        })
                        .memoCardStyle()
                        .onAppear {
                            loadNextPageIfNeeded(current: memo)
                        }
                    }
                }

                if isLoadingPage {
                    ProgressView()
                        .padding(.top, 8)
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

    // MARK: - Paging

    private func resetAndReload() {
        displayedMemos = []
        loadedCount = 0
        pinnedLoadedCount = 0
        unpinnedLoadedCount = 0
        pinnedExhausted = false
        canLoadMore = true
        isLoadingPage = false
        refreshTotalCount()
        loadNextPage()
    }

    private func loadNextPageIfNeeded(current memo: Memo) {
        guard canLoadMore, !isLoadingPage else { return }
        guard let idx = displayedMemos.firstIndex(where: {
            $0.persistentModelID == memo.persistentModelID
        }) else { return }
        if idx >= displayedMemos.count - 8 {
            loadNextPage()
        }
    }

    private func loadNextPage() {
        guard canLoadMore, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        if let tag = selectedTag {
            let sorted = sortMemos(tag.memos)
            let page = Array(sorted.dropFirst(loadedCount).prefix(pageSize))
            displayedMemos.append(contentsOf: page)
            loadedCount += page.count
            canLoadMore = page.count == pageSize && loadedCount < sorted.count
            return
        }

        do {
            var page: [Memo] = []
            var remaining = pageSize

            if !pinnedExhausted {
                var pinnedDescriptor = FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.isPinned == true },
                    sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                )
                pinnedDescriptor.fetchOffset = pinnedLoadedCount
                pinnedDescriptor.fetchLimit = remaining

                let pinnedPage = try modelContext.fetch(pinnedDescriptor)
                page.append(contentsOf: pinnedPage)
                pinnedLoadedCount += pinnedPage.count
                remaining -= pinnedPage.count
                if pinnedPage.count < pageSize {
                    pinnedExhausted = true
                }
            }

            if remaining > 0 {
                var unpinnedDescriptor = FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.isPinned == false },
                    sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                )
                unpinnedDescriptor.fetchOffset = unpinnedLoadedCount
                unpinnedDescriptor.fetchLimit = remaining

                let unpinnedPage = try modelContext.fetch(unpinnedDescriptor)
                page.append(contentsOf: unpinnedPage)
                unpinnedLoadedCount += unpinnedPage.count
            }

            displayedMemos.append(contentsOf: page)
            canLoadMore = displayedMemos.count < totalMemoCount
        } catch {
            canLoadMore = false
        }
    }

    private func refreshTotalCount() {
        guard selectedTag == nil else {
            totalMemoCount = 0
            return
        }
        do {
            let descriptor = FetchDescriptor<Memo>()
            totalMemoCount = try modelContext.fetchCount(descriptor)
        } catch {
            totalMemoCount = displayedMemos.count
        }
    }

    private func sortMemos(_ memos: [Memo]) -> [Memo] {
        memos.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.persistentModelID.hashValue > rhs.persistentModelID.hashValue
        }
    }
}
