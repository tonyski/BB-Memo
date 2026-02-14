//
//  ContentView.swift
//  BB-Memo
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

/// 主视图 — 根据平台自动切换布局
struct ContentView: View {
    @State private var showComposer = false
    @State private var showSidebar = false

    var body: some View {
        #if os(macOS)
        MacContentView(showComposer: $showComposer)
        #else
        NavigationStack {
            ZStack(alignment: .bottom) {
                MemoTimelineView(showSidebar: $showSidebar)

                // 底部浮动按钮
                if !showSidebar {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.onBrandAccent)
                            .frame(width: 54, height: 54)
                            .background(AppTheme.brandAccent)
                            .clipShape(Circle())
                            .shadow(color: AppTheme.brandAccent.opacity(0.3), radius: 10, y: 5)
                    }
                    .accessibilityLabel("新建笔记")
                    .accessibilityHint("打开编辑器，新建一条笔记")
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.default, value: showSidebar)
            .sheet(isPresented: $showComposer) {
                MemoEditorSheetView(memo: nil)
            }
        }
        #endif
    }
}

// MARK: - macOS 布局

#if os(macOS)
struct MacContentView: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Query(
        sort: [
            SortDescriptor(\Tag.usageCount, order: .reverse),
            SortDescriptor(\Tag.name, order: .forward)
        ]
    ) private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext

    @Binding var showComposer: Bool
    @State private var selectedTag: Tag?
    @State private var isRecycleBinSelected = false
    @State private var memoToEdit: Memo?
    @State private var searchText = ""
    @State private var tagSearchText = ""
    @State private var isTagSearchExpanded = false
    @FocusState private var isTagSearchFocused: Bool

    @State private var showSettings = false
    @State private var tagPendingDeletion: Tag?

    private var filteredMemos: [Memo] {
        if isRecycleBinSelected {
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let recycled = memos.filter { $0.isInRecycleBin }
            let matched: [Memo]
            if keyword.isEmpty {
                matched = recycled
            } else {
                matched = recycled.filter {
                    $0.content.localizedCaseInsensitiveContains(keyword)
                    || $0.tagsList.contains { $0.name.localizedCaseInsensitiveContains(keyword) }
                }
            }
            return MemoFilter.sortRecycleBin(matched)
        }
        return MemoFilter.apply(memos, tag: selectedTag, searchText: searchText)
    }

    private var activeMemoCount: Int {
        memos.count(where: { !$0.isInRecycleBin })
    }

    private var deletedMemoCount: Int {
        memos.count(where: { $0.isInRecycleBin })
    }

    private var filteredTags: [Tag] {
        let keyword = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            memoDetail
        }
        .searchable(text: $searchText, prompt: "搜索笔记内容或标签")
        .sheet(isPresented: $showComposer) {
            MemoEditorSheetView(memo: nil)
        }
        .sheet(item: $memoToEdit) { memo in
            MemoEditorSheetView(memo: memo)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
        .onAppear {
            DispatchQueue.main.async {
                isTagSearchFocused = false
            }
        }
        .confirmationDialog(
            "删除标签？",
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { tagPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除标签", role: .destructive) {
                guard let tagPendingDeletion else { return }
                collapseTagSearch()
                deleteTag(tagPendingDeletion)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅移除该标签，不会删除关联笔记。")
        }
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("BB Memo")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.brandAccent)
                Spacer()
                Button {
                    collapseTagSearch()
                    showComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(AppTheme.brandAccent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建笔记")
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                MacSidebarRow(
                    title: "全部笔记",
                    count: activeMemoCount,
                    isSelected: selectedTag == nil && !isRecycleBinSelected,
                    icon: "tray.full"
                ) {
                    collapseTagSearch()
                    selectedTag = nil
                    isRecycleBinSelected = false
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Text("标签")
                        .font(.system(size: 11, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Rectangle()
                        .fill(.secondary.opacity(0.18))
                        .frame(height: 1)
                    Button {
                        withAnimation(AppTheme.snappy) {
                            let shouldExpand = !isTagSearchExpanded
                            isTagSearchExpanded = shouldExpand
                            if !shouldExpand {
                                collapseTagSearch()
                            }
                        }
                        if isTagSearchExpanded {
                            DispatchQueue.main.async {
                                isTagSearchFocused = true
                            }
                        }
                    } label: {
                        Image(systemName: isTagSearchExpanded ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isTagSearchExpanded ? "收起标签搜索" : "展开标签搜索")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, isTagSearchExpanded ? 6 : 2)

                if isTagSearchExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("搜索标签", text: $tagSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: AppTheme.Layout.fontDesign))
                            .focused($isTagSearchFocused)
                        if !tagSearchText.isEmpty {
                            Button {
                                tagSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清空标签搜索")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if filteredTags.isEmpty {
                            Text(tagSearchText.isEmpty ? "暂无标签" : "没有匹配标签")
                                .font(.system(size: 12, design: AppTheme.Layout.fontDesign))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(filteredTags) { tag in
                                MacSidebarRow(
                                    title: tag.name,
                                    count: tag.usageCount,
                                    isSelected: selectedTag?.persistentModelID == tag.persistentModelID,
                                    icon: "#",
                                    isTag: true,
                                    onDeleteRequest: {
                                        tagPendingDeletion = tag
                                    }
                                ) {
                                    collapseTagSearch()
                                    selectedTag = tag
                                    isRecycleBinSelected = false
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isTagSearchExpanded {
                        collapseTagSearch()
                    }
                }
                MacSidebarSectionLabel(title: "工具")

                MacSidebarRow(
                    title: "回收站",
                    count: deletedMemoCount,
                    isSelected: isRecycleBinSelected,
                    icon: "trash",
                    accentColor: .orange
                ) {
                    collapseTagSearch()
                    selectedTag = nil
                    isRecycleBinSelected = true
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            Button {
                collapseTagSearch()
                showSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape").font(.subheadline)
                    Text("设置").font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 260)
    }

    // MARK: - 内容区

    private var memoDetail: some View {
        Group {
            if filteredMemos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: selectedTag != nil ? "tag" : (isRecycleBinSelected ? "trash" : "square.and.pencil"))
                        .font(.system(size: 40))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    Text(
                        selectedTag != nil
                        ? "该标签下暂无内容"
                        : (isRecycleBinSelected ? "回收站为空" : "点击 ⌘N 新建笔记")
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Layout.cardSpacing) {
                        ForEach(filteredMemos, id: \.persistentModelID) { memo in
                            MemoCardView(
                                memo: memo,
                                mode: isRecycleBinSelected ? .recycleBin : .normal,
                                onEdit: isRecycleBinSelected ? nil : {
                                    memoToEdit = memo
                                },
                                onTagTap: { tag in
                                    selectedTag = tag
                                    isRecycleBinSelected = false
                                }
                            )
                            .memoCardStyle()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .background(AppTheme.background)
            }
        }
        .navigationTitle(
            isRecycleBinSelected
            ? "回收站"
            : (selectedTag.map { "# \($0.name)" } ?? "全部笔记")
        )
        .toolbar {
            if selectedTag != nil || isRecycleBinSelected {
                ToolbarItem {
                    Button {
                        selectedTag = nil
                        isRecycleBinSelected = false
                    } label: {
                        Label("清除筛选", systemImage: "xmark.circle")
                    }
                    .help("清除标签筛选")
                }
            }
        }
    }

    private func deleteTag(_ tag: Tag) {
        let wasSelected = selectedTag?.persistentModelID == tag.persistentModelID
        do {
            try MemoMutationService.deleteTag(tag, context: modelContext)
            if wasSelected {
                selectedTag = nil
            }
            AppNotifications.postMemoDataChanged()
        } catch {
            print("MacContentView deleteTag save failed: \(error)")
        }
        tagPendingDeletion = nil
    }

    private func collapseTagSearch() {
        tagSearchText = ""
        isTagSearchExpanded = false
        isTagSearchFocused = false
    }
}
#endif

// MARK: - Helper Views

#if os(macOS)
struct MacSidebarRow: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let icon: String
    var isTag: Bool = false
    var accentColor: Color = AppTheme.brandAccent
    var onDeleteRequest: (() -> Void)? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isTag {
                    Text(icon)
                        .font(.system(size: 13, weight: .bold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(isSelected ? accentColor : .secondary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? accentColor : .secondary)
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(isSelected ? 0.12 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isTag, let onDeleteRequest {
                Button(role: .destructive) {
                    onDeleteRequest()
                } label: {
                    Label("删除标签", systemImage: "trash")
                }
            }
        }
    }
}

private struct MacSidebarSectionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Rectangle()
                .fill(.secondary.opacity(0.18))
                .frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
#endif


#Preview {
    ContentView()
        .modelContainer(for: [Memo.self, Tag.self], inMemory: true)
}
