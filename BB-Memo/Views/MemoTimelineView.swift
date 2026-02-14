//
//  MemoTimelineView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import CoreData
import Combine

/// BB 主页 — 时间线 + 标签侧栏
struct MemoTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    private struct PagingState {
        var tagLoadedCount = 0
        var pinnedLoadedCount = 0
        var unpinnedLoadedCount = 0
        var pinnedExhausted = false
        var canLoadMore = true
        var isLoadingPage = false

        mutating func reset() {
            tagLoadedCount = 0
            pinnedLoadedCount = 0
            unpinnedLoadedCount = 0
            pinnedExhausted = false
            canLoadMore = true
            isLoadingPage = false
        }
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
    @State private var loadPageTask: Task<Void, Never>?

    private let pageSize = 40
    private let topBarFadeAnimation = Animation.easeOut(duration: 0.12)
    private var visibleDisplayedMemos: [Memo] {
        displayedMemos.filter { isRecycleBinSelected ? $0.isInRecycleBin : !$0.isInRecycleBin }
    }

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
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
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
        .onReceive(NotificationCenter.default.publisher(for: .memoDataChanged).receive(on: RunLoop.main)) { _ in
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            scheduleReload()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                scheduleReload()
            }
        }
        .onDisappear {
            reloadTask?.cancel()
            loadPageTask?.cancel()
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
                if visibleDisplayedMemos.isEmpty && !paging.isLoadingPage {
                    emptyState
                } else {
                    ForEach(visibleDisplayedMemos, id: \.persistentModelID) { memo in
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

    // MARK: - Paging

    private func resetAndReload() {
        reloadTask?.cancel()
        loadPageTask?.cancel()
        if isRecycleBinSelected {
            loadRecycleBin()
            return
        }
        displayedMemos = []
        selectedTagSortedMemos = selectedTag.map { MemoFilter.sort($0.memosList.filter { !$0.isInRecycleBin }) } ?? []
        paging.reset()
        refreshTotalCount()
        loadNextPage()
    }

    private func loadNextPageIfNeeded(current memo: Memo) {
        guard !isRecycleBinSelected else { return }
        guard paging.canLoadMore, !paging.isLoadingPage else { return }
        let visible = visibleDisplayedMemos
        let triggerIndex = max(visible.count - 8, 0)
        guard visible.indices.contains(triggerIndex) else { return }
        let triggerMemoID = visible[triggerIndex].persistentModelID
        if memo.persistentModelID == triggerMemoID {
            loadNextPage()
        }
    }

    private func loadNextPage() {
        guard !isRecycleBinSelected else { return }
        guard paging.canLoadMore, !paging.isLoadingPage else { return }
        paging.isLoadingPage = true

        if selectedTag != nil {
            let page = Array(selectedTagSortedMemos.dropFirst(paging.tagLoadedCount).prefix(pageSize))
            displayedMemos.append(contentsOf: page)
            paging.tagLoadedCount += page.count
            paging.canLoadMore = page.count == pageSize && paging.tagLoadedCount < selectedTagSortedMemos.count
            paging.isLoadingPage = false
            return
        }

        struct PageSlice: Sendable {
            let stableIDs: [UUID]
            let pinnedCount: Int
            let unpinnedCount: Int
            let pinnedExhausted: Bool
        }

        let pageSize = self.pageSize
        let container = modelContext.container
        let pinnedLoadedCount = paging.pinnedLoadedCount
        let unpinnedLoadedCount = paging.unpinnedLoadedCount
        let pinnedExhausted = paging.pinnedExhausted
        let currentTotalCount = totalMemoCount

        loadPageTask?.cancel()
        loadPageTask = Task(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                var page: [Memo] = []
                var remaining = pageSize
                var loadedPinnedCount = 0
                var loadedUnpinnedCount = 0
                var didExhaustPinned = pinnedExhausted

                if !didExhaustPinned {
                    var pinnedDescriptor = FetchDescriptor<Memo>(
                        predicate: #Predicate<Memo> { $0.isPinned == true && $0.deletedAt == nil },
                        sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                    )
                    pinnedDescriptor.fetchOffset = pinnedLoadedCount
                    pinnedDescriptor.fetchLimit = remaining

                    let pinnedPage = try context.fetch(pinnedDescriptor)
                    page.append(contentsOf: pinnedPage)
                    loadedPinnedCount = pinnedPage.count
                    remaining -= pinnedPage.count
                    if pinnedPage.count < pageSize {
                        didExhaustPinned = true
                    }
                }

                if remaining > 0 {
                    var unpinnedDescriptor = FetchDescriptor<Memo>(
                        predicate: #Predicate<Memo> { $0.isPinned == false && $0.deletedAt == nil },
                        sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                    )
                    unpinnedDescriptor.fetchOffset = unpinnedLoadedCount
                    unpinnedDescriptor.fetchLimit = remaining

                    let unpinnedPage = try context.fetch(unpinnedDescriptor)
                    page.append(contentsOf: unpinnedPage)
                    loadedUnpinnedCount = unpinnedPage.count
                }

                let pageSlice = PageSlice(
                    stableIDs: page.map(\.stableID),
                    pinnedCount: loadedPinnedCount,
                    unpinnedCount: loadedUnpinnedCount,
                    pinnedExhausted: didExhaustPinned
                )

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let page = fetchMemosByStableIDs(pageSlice.stableIDs)
                    displayedMemos.append(contentsOf: page)
                    paging.pinnedLoadedCount += pageSlice.pinnedCount
                    paging.unpinnedLoadedCount += pageSlice.unpinnedCount
                    paging.pinnedExhausted = pageSlice.pinnedExhausted
                    paging.canLoadMore = displayedMemos.count < currentTotalCount
                    paging.isLoadingPage = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    paging.canLoadMore = false
                    paging.isLoadingPage = false
                }
            }
        }
    }

    private func refreshTotalCount() {
        if isRecycleBinSelected {
            do {
                let descriptor = FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.deletedAt != nil }
                )
                totalMemoCount = try modelContext.fetchCount(descriptor)
            } catch {
                totalMemoCount = displayedMemos.count
            }
            return
        }
        guard selectedTag == nil else {
            totalMemoCount = 0
            return
        }
        do {
            let descriptor = FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { $0.deletedAt == nil }
            )
            totalMemoCount = try modelContext.fetchCount(descriptor)
        } catch {
            totalMemoCount = displayedMemos.count
        }
    }

    private func scheduleReload(delay: Duration = .milliseconds(280)) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if displayedMemos.isEmpty {
                    resetAndReload()
                } else {
                    refreshSilently()
                }
            }
        }
    }

    /// 刷新已有列表时静默更新，避免先清空数据触发 loading 闪烁
    private func refreshSilently() {
        loadPageTask?.cancel()

        if isRecycleBinSelected {
            loadRecycleBin()
            return
        }

        if selectedTag != nil {
            let sorted = selectedTag.map { MemoFilter.sort($0.memosList.filter { !$0.isInRecycleBin }) } ?? []
            let firstPage = Array(sorted.prefix(pageSize))
            selectedTagSortedMemos = sorted
            displayedMemos = firstPage
            paging.reset()
            paging.tagLoadedCount = firstPage.count
            paging.canLoadMore = firstPage.count == pageSize && firstPage.count < sorted.count
            refreshTotalCount()
            return
        }

        struct FirstPageSnapshot: Sendable {
            let stableIDs: [UUID]
            let pinnedCount: Int
            let unpinnedCount: Int
            let pinnedExhausted: Bool
        }

        let container = modelContext.container
        let pageSize = self.pageSize

        loadPageTask = Task(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                var page: [Memo] = []
                var remaining = pageSize
                var loadedPinnedCount = 0
                var loadedUnpinnedCount = 0
                var didExhaustPinned = false

                var pinnedDescriptor = FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.isPinned == true && $0.deletedAt == nil },
                    sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                )
                pinnedDescriptor.fetchOffset = 0
                pinnedDescriptor.fetchLimit = remaining
                let pinnedPage = try context.fetch(pinnedDescriptor)
                page.append(contentsOf: pinnedPage)
                loadedPinnedCount = pinnedPage.count
                remaining -= pinnedPage.count
                if pinnedPage.count < pageSize {
                    didExhaustPinned = true
                }

                if remaining > 0 {
                    var unpinnedDescriptor = FetchDescriptor<Memo>(
                        predicate: #Predicate<Memo> { $0.isPinned == false && $0.deletedAt == nil },
                        sortBy: [SortDescriptor(\Memo.createdAt, order: .reverse)]
                    )
                    unpinnedDescriptor.fetchOffset = 0
                    unpinnedDescriptor.fetchLimit = remaining
                    let unpinnedPage = try context.fetch(unpinnedDescriptor)
                    page.append(contentsOf: unpinnedPage)
                    loadedUnpinnedCount = unpinnedPage.count
                }

                let snapshot = FirstPageSnapshot(
                    stableIDs: page.map(\.stableID),
                    pinnedCount: loadedPinnedCount,
                    unpinnedCount: loadedUnpinnedCount,
                    pinnedExhausted: didExhaustPinned
                )

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let firstPage = fetchMemosByStableIDs(snapshot.stableIDs)
                    displayedMemos = firstPage
                    paging.reset()
                    paging.pinnedLoadedCount = snapshot.pinnedCount
                    paging.unpinnedLoadedCount = snapshot.unpinnedCount
                    paging.pinnedExhausted = snapshot.pinnedExhausted
                    refreshTotalCount()
                    paging.canLoadMore = displayedMemos.count < totalMemoCount
                }
            } catch {
                // 静默刷新失败时保留当前列表，避免界面抖动
            }
        }
    }

    private func fetchMemosByStableIDs(_ stableIDs: [UUID]) -> [Memo] {
        guard !stableIDs.isEmpty else { return [] }
        let ids = stableIDs
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { memo in
                ids.contains(memo.stableID)
            }
        )
        let memos = (try? modelContext.fetch(descriptor)) ?? []
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

    private func loadRecycleBin() {
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { $0.deletedAt != nil },
            sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse)]
        )
        let recycled = (try? modelContext.fetch(descriptor)) ?? []
        withAnimation(AppTheme.snappy) {
            displayedMemos = MemoFilter.sortRecycleBin(recycled)
        }
        selectedTagSortedMemos = []
        paging.reset()
        paging.canLoadMore = false
        paging.isLoadingPage = false
        totalMemoCount = displayedMemos.count
    }

    private func removeMemoFromDisplayedList(stableID: UUID) {
        withAnimation(AppTheme.spring) {
            displayedMemos.removeAll { $0.stableID == stableID }
            selectedTagSortedMemos.removeAll { $0.stableID == stableID }
            totalMemoCount = max(totalMemoCount - 1, 0)
        }
    }
}
