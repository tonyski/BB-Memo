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
    @Environment(\.scenePhase) private var scenePhase

    private struct PagingState {
        var tagLoadedCount = 0
        var cursor = MemoPageCursor()
        var canLoadMore = true
        var isLoadingPage = false
    }

    @State private var memoToEdit: Memo?
    @Binding var showSidebar: Bool
    @State private var selectedTag: Tag?
    @State private var isRecycleBinSelected = false
    @State private var displayedMemos: [Memo] = []
    @State private var selectedTagSortedMemos: [Memo] = []
    @State private var paging = PagingState()
    @State private var totalMemoCount = 0
    @State private var reloadTask: Task<Void, Never>?
    @State private var loadErrorMessage: String?

    private let pageSize = 40
    private let topBarFadeAnimation = Animation.easeOut(duration: 0.12)

    var body: some View {
        ZStack {
            memoList
                .background(AppTheme.background)

            // ── 侧边栏 ──
            TagSidebarView(
                selectedTag: $selectedTag,
                isRecycleBinSelected: $isRecycleBinSelected,
                isOpen: $showSidebar
            )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBarInset
        }
        .overlay(alignment: .leading) {
            edgeOpenSidebarHotZone
        }
        .navigationBarHidden(true)
        .sheet(item: $memoToEdit) { memo in
            MemoEditorSheetView(memo: memo)
        }
        .onAppear {
            if displayedMemos.isEmpty {
                resetAndReload()
            }
        }
        .onChange(of: selectedTag?.persistentModelID) { _, _ in
            if selectedTag != nil {
                isRecycleBinSelected = false
            }
            resetAndReload()
        }
        .onChange(of: isRecycleBinSelected) { _, _ in
            resetAndReload()
        }
        .onReceive(AppNotifications.dataChanges) {
            scheduleReload()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                scheduleReload()
            }
        }
        .onDisappear {
            reloadTask?.cancel()
        }
    }

    // MARK: - 顶部栏

    private var topBarInset: some View {
        VStack(spacing: 0) {
            topBar
                .background(.ultraThinMaterial)
            Divider().opacity(0.5)
        }
        .opacity(showSidebar ? 0 : 1)
        .allowsHitTesting(!showSidebar)
        .animation(topBarFadeAnimation, value: showSidebar)
    }

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
            .accessibilityLabel(showSidebar ? "关闭标签侧栏" : "打开标签侧栏")
            .padding(.leading, 8)

            Spacer()

            // 标题
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(topBarTitle)
                        .font(.system(size: 17, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(.primary)
                    
                    if selectedTag != nil || isRecycleBinSelected {
                        Button {
                            withAnimation(AppTheme.spring) {
                                selectedTag = nil
                                isRecycleBinSelected = false
                            }
                            HapticFeedback.light.play()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除标签筛选")
                    }
                }
                
                if selectedTag == nil {
                    Text("\(totalMemoCount) 条笔记")
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
            .accessibilityLabel("搜索")
            .padding(.trailing, 8)
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Memo 列表

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Layout.cardSpacing) {
                if displayedMemos.isEmpty && !paging.isLoadingPage {
                    if loadErrorMessage != nil {
                        loadErrorState
                    } else {
                        emptyState
                    }
                } else {
                    ForEach(displayedMemos, id: \.persistentModelID) { memo in
                        MemoCardView(
                            memo: memo,
                            mode: isRecycleBinSelected ? .recycleBin : .normal,
                            onEdit: isRecycleBinSelected ? nil : {
                                memoToEdit = memo
                            },
                            onTagTap: { tag in
                                selectedTag = tag
                                isRecycleBinSelected = false
                            },
                            onMemoRemoved: { stableID in
                                removeMemoFromDisplayedList(stableID: stableID)
                            }
                        )
                        .memoCardStyle()
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            )
                        )
                        .onAppear {
                            loadNextPageIfNeeded(current: memo)
                        }
                    }
                }

                if !displayedMemos.isEmpty, loadErrorMessage != nil {
                    loadErrorState
                        .padding(.top, 12)
                }

                // 底部间距
                Spacer().frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .animation(AppTheme.spring, value: displayedMemos.map(\.stableID))
        }
        .scrollIndicators(.hidden)
    }

    private var edgeOpenSidebarHotZone: some View {
        Color.clear
            .frame(width: 18)
            .contentShape(Rectangle())
            .allowsHitTesting(!showSidebar)
            .gesture(edgeOpenSidebarGesture)
    }

    private var edgeOpenSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !showSidebar else { return }
                let horizontalDistance = value.translation.width
                let verticalDistance = abs(value.translation.height)
                let isMostlyHorizontal = abs(horizontalDistance) > verticalDistance * 1.4
                guard isMostlyHorizontal, horizontalDistance > 80 else { return }

                withAnimation(AppTheme.spring) {
                    showSidebar = true
                }
            }
    }

    // MARK: - 空状态

    private var topBarTitle: String {
        if isRecycleBinSelected { return "回收站" }
        if let selectedTag { return "#\(selectedTag.name)" }
        return "BB Memo"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: isRecycleBinSelected ? "trash" : "pencil.and.outline")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.brandAccent.opacity(0.2))
            
            Text(
                selectedTag != nil
                ? "该标签下暂无内容"
                : (isRecycleBinSelected ? "回收站为空" : "捕捉此刻的灵感")
            )
                .font(.system(size: 15, weight: .medium, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
    }

    private var loadErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppTheme.warning)
            Text(loadErrorMessage ?? "读取笔记失败")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重试") {
                resetAndReload()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, displayedMemos.isEmpty ? 120 : 20)
    }

    // MARK: - Paging

    private func resetAndReload() {
        reloadTask?.cancel()
        loadErrorMessage = nil
        if isRecycleBinSelected {
            loadRecycleBin()
            return
        }

        if let selectedTag {
            selectedTagSortedMemos = MemoFilter.apply(selectedTag.memosList)
            totalMemoCount = selectedTagSortedMemos.count
            let firstPage = Array(selectedTagSortedMemos.prefix(pageSize))
            displayedMemos = firstPage
            paging = PagingState(
                tagLoadedCount: firstPage.count,
                canLoadMore: firstPage.count < selectedTagSortedMemos.count
            )
            return
        }

        selectedTagSortedMemos = []
        do {
            totalMemoCount = try MemoQueryService.activeCount(in: modelContext)
            var freshPaging = PagingState()
            displayedMemos = try MemoQueryService.fetchActivePage(
                in: modelContext,
                cursor: &freshPaging.cursor,
                limit: pageSize
            )
            freshPaging.canLoadMore = displayedMemos.count < totalMemoCount
            paging = freshPaging
        } catch {
            handleLoadError(error)
        }
    }

    private func loadNextPageIfNeeded(current memo: Memo) {
        guard paging.canLoadMore, !paging.isLoadingPage else { return }
        let triggerIndex = max(displayedMemos.count - 8, 0)
        guard displayedMemos.indices.contains(triggerIndex) else { return }
        let triggerMemoID = displayedMemos[triggerIndex].persistentModelID
        if memo.persistentModelID == triggerMemoID {
            loadNextPage()
        }
    }

    private func loadNextPage() {
        guard paging.canLoadMore, !paging.isLoadingPage else { return }
        if isRecycleBinSelected {
            paging.isLoadingPage = true
            defer { paging.isLoadingPage = false }
            do {
                let page = try MemoQueryService.fetchRecycleBinPage(
                    in: modelContext,
                    cursor: &paging.cursor,
                    limit: pageSize
                )
                displayedMemos.append(contentsOf: page)
                paging.canLoadMore = paging.cursor.recycleBinOffset < totalMemoCount
                loadErrorMessage = nil
            } catch {
                handleLoadError(error)
            }
            return
        }

        if selectedTag != nil {
            let page = Array(selectedTagSortedMemos.dropFirst(paging.tagLoadedCount).prefix(pageSize))
            displayedMemos.append(contentsOf: page)
            paging.tagLoadedCount += page.count
            paging.canLoadMore = paging.tagLoadedCount < selectedTagSortedMemos.count
            return
        }

        paging.isLoadingPage = true
        defer { paging.isLoadingPage = false }
        do {
            let page = try MemoQueryService.fetchActivePage(
                in: modelContext,
                cursor: &paging.cursor,
                limit: pageSize
            )
            displayedMemos.append(contentsOf: page)
            paging.canLoadMore = paging.cursor.activeLoadedCount < totalMemoCount
            loadErrorMessage = nil
        } catch {
            handleLoadError(error)
        }
    }

    private func scheduleReload(delay: Duration = .milliseconds(120)) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            resetAndReload()
        }
    }

    private func loadRecycleBin() {
        do {
            totalMemoCount = try MemoQueryService.recycleBinCount(in: modelContext)
            var freshPaging = PagingState()
            let firstPage = try MemoQueryService.fetchRecycleBinPage(
                in: modelContext,
                cursor: &freshPaging.cursor,
                limit: pageSize
            )
            freshPaging.canLoadMore =
                freshPaging.cursor.recycleBinOffset < totalMemoCount
            withAnimation(AppTheme.snappy) {
                displayedMemos = firstPage
            }
            selectedTagSortedMemos = []
            paging = freshPaging
            loadErrorMessage = nil
        } catch {
            handleLoadError(error)
        }
    }

    private func handleLoadError(_ error: Error) {
        loadErrorMessage = "读取笔记失败，请重试。"
        print("MemoTimelineView fetch failed: \(error)")
    }

    private func removeMemoFromDisplayedList(stableID: UUID) {
        withAnimation(AppTheme.spring) {
            displayedMemos.removeAll { $0.stableID == stableID }
            selectedTagSortedMemos.removeAll { $0.stableID == stableID }
            totalMemoCount = max(totalMemoCount - 1, 0)
        }
    }
}
