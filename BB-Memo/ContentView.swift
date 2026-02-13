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
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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
    @State private var memoToEdit: Memo?
    @State private var searchText = ""

    @State private var showSettings = false
    @State private var tagPendingDeletion: Tag?

    private var filteredMemos: [Memo] {
        MemoFilter.apply(memos, tag: selectedTag, searchText: searchText)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            memoDetail
        }
        .searchable(text: $searchText, prompt: "搜索内容或标签")
        .sheet(isPresented: $showComposer) {
            MemoEditorSheetView(memo: nil)
        }
        .sheet(item: $memoToEdit) { memo in
            MemoEditorSheetView(memo: memo)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
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
                deleteTag(tagPendingDeletion)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅移除该标签，不会删除已关联的 Memo。")
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
                Button { showComposer = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(AppTheme.brandAccent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()

            List {
                MacSidebarRow(
                    title: "全部思考",
                    count: memos.count,
                    isSelected: selectedTag == nil,
                    icon: "tray.full"
                ) {
                    selectedTag = nil
                }

                if !allTags.isEmpty {
                    Section("标签") {
                        ForEach(allTags) { tag in
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
                                selectedTag = tag
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button { showSettings = true } label: {
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
                    Image(systemName: selectedTag != nil ? "tag" : "square.and.pencil")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    Text(selectedTag != nil ? "该标签下暂无内容" : "点击 ⌘N 开始记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Layout.cardSpacing) {
                        ForEach(filteredMemos, id: \.persistentModelID) { memo in
                            MemoCardView(memo: memo, onEdit: {
                                memoToEdit = memo
                            }, onTagTap: { tag in
                                selectedTag = tag
                            })
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
        .navigationTitle(selectedTag.map { "# \($0.name)" } ?? "全部思考")
        .toolbar {
            if selectedTag != nil {
                ToolbarItem {
                    Button {
                        selectedTag = nil
                    } label: {
                        Label("清除筛选", systemImage: "xmark.circle")
                    }
                    .help("清除标签筛选")
                }
            }
        }
    }

    private func deleteTag(_ tag: Tag) {
        if selectedTag?.persistentModelID == tag.persistentModelID {
            selectedTag = nil
        }
        modelContext.delete(tag)
        try? modelContext.save()
        tagPendingDeletion = nil
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
    var onDeleteRequest: (() -> Void)? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: AppTheme.Layout.fontDesign))
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 10, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                if isTag {
                    Text(icon)
                        .font(.system(size: 13, weight: .bold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(AppTheme.brandAccent)
                } else {
                    Image(systemName: icon)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? AppTheme.brandAccent.opacity(0.1) : Color.clear)
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
#endif


#Preview {
    ContentView()
        .modelContainer(for: [Memo.self, Tag.self], inMemory: true)
}
