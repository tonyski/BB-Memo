//
//  TagSidebarView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import CoreData
import Combine

/// 左侧滑出标签筛选菜单
struct TagSidebarView: View {
    @Query(
        sort: [
            SortDescriptor(\Tag.usageCount, order: .reverse),
            SortDescriptor(\Tag.name, order: .forward)
        ]
    ) private var allTags: [Tag]
    @Binding var selectedTag: Tag?
    @Binding var isRecycleBinSelected: Bool
    @Binding var isOpen: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false
    @State private var tagPendingDeletion: Tag?
    @State private var activeMemoCount = 0
    @State private var deletedMemoCount = 0
    @State private var tagSearchText = ""
    @State private var isTagSearchExpanded = false
    @FocusState private var isTagSearchFocused: Bool
    
    private var filteredTags: [Tag] {
        let keyword = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }
    
    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = idealSidebarWidth(totalWidth: proxy.size.width)
            let topSafeInset = proxy.safeAreaInsets.top
            let bottomSafeInset = proxy.safeAreaInsets.bottom
            ZStack(alignment: .leading) {
                // 半透明背景遮罩 + 模糊
                if isOpen {
                    Color.black.opacity(0.15)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(AppTheme.spring) {
                                isOpen = false
                            }
                        }
                        .transition(.opacity)
                }

                // 侧边栏面板
                HStack(spacing: 0) {
                    sidebarContent(
                        width: sidebarWidth,
                        topInset: topSafeInset,
                        bottomInset: bottomSafeInset
                    )
                        .background(AppTheme.cardBackground)
                        .ignoresSafeArea() // 修复上下缺口
                        .premiumShadow()
                    Spacer(minLength: 0)
                }
                .offset(x: isOpen ? 0 : -sidebarWidth)
            }
        }
        .animation(AppTheme.spring, value: isOpen)
        // 关键修复：当关闭时，侧边栏不应拦截主界面的触摸
        .allowsHitTesting(isOpen)
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
        .onAppear {
            refreshMemoCounts()
        }
        .onChange(of: isOpen) { _, isNowOpen in
            if isNowOpen {
                refreshMemoCounts()
                isTagSearchFocused = false
            } else {
                collapseTagSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoDataChanged).receive(on: RunLoop.main)) { _ in
            refreshMemoCounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            refreshMemoCounts()
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
            Text("仅移除该标签，不会删除关联笔记。")
        }
    }

    // MARK: - 侧边栏内容

    private func sidebarContent(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部区域
            headerSection(topInset: topInset)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                SidebarItemView(
                    title: "全部笔记",
                    icon: (selectedTag == nil && !isRecycleBinSelected) ? "tray.full.fill" : "tray.full",
                    count: activeMemoCount,
                    isSelected: selectedTag == nil && !isRecycleBinSelected,
                    action: {
                        collapseTagSearch()
                        selectedTag = nil
                        isRecycleBinSelected = false
                        closeSidebar()
                    }
                )

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
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, isTagSearchExpanded ? 6 : 2)

                if isTagSearchExpanded {
                    tagSearchField
                        .padding(.horizontal, 10)
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
                                SidebarItemView(
                                    title: tag.name,
                                    icon: "#",
                                    isTag: true,
                                    count: tag.usageCount,
                                    isSelected: selectedTag?.persistentModelID == tag.persistentModelID,
                                    action: {
                                        collapseTagSearch()
                                        selectedTag = tag
                                        isRecycleBinSelected = false
                                        closeSidebar()
                                    },
                                    onDeleteRequest: {
                                        tagPendingDeletion = tag
                                    }
                                )
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity, alignment: .top)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isTagSearchExpanded {
                            collapseTagSearch()
                        }
                    }
                )

                Spacer(minLength: 8)
                SidebarSectionLabel(title: "工具")
                    .padding(.top, 0)

                SidebarItemView(
                    title: "回收站",
                    icon: "trash",
                    count: deletedMemoCount,
                    isSelected: isRecycleBinSelected,
                    accentColor: .orange,
                    action: {
                        collapseTagSearch()
                        selectedTag = nil
                        isRecycleBinSelected = true
                        closeSidebar()
                    }
                )
                .padding(.bottom, max(10, bottomInset * 0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: width)
    }

    private var tagSearchField: some View {
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
    }

    private func idealSidebarWidth(totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * 0.82, 248), 340)
    }

    private func refreshMemoCounts() {
        do {
            activeMemoCount = try modelContext.fetchCount(
                FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.deletedAt == nil }
                )
            )
            deletedMemoCount = try modelContext.fetchCount(
                FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.deletedAt != nil }
                )
            )
        } catch {
            activeMemoCount = 0
            deletedMemoCount = 0
        }
    }

    private func closeSidebar() {
        collapseTagSearch()
        withAnimation(AppTheme.spring) {
            isOpen = false
        }
        HapticFeedback.selection.play()
    }

    private func collapseTagSearch() {
        tagSearchText = ""
        isTagSearchExpanded = false
        isTagSearchFocused = false
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
            print("TagSidebarView deleteTag save failed: \(error)")
        }
        HapticFeedback.medium.play()
        refreshMemoCounts()
        tagPendingDeletion = nil
    }

    private func headerSection(topInset: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BB Memo")
                    .font(.system(size: 28, weight: .bold, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(AppTheme.brandGradient)
                Text("\(allTags.count) 个标签")
                    .font(.system(size: 11, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                showSettings = true
                HapticFeedback.light.play()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 24)
        .padding(.bottom, 10)
    }
}

// MARK: - Sidebar Item View Component

struct SidebarItemView: View {
    let title: String
    let icon: String // 可以是 systemName 或 文字符号
    var isTag: Bool = false
    var count: Int? = nil
    let isSelected: Bool
    var accentColor: Color = AppTheme.brandAccent
    let action: () -> Void
    var onDeleteRequest: (() -> Void)? = nil
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                Group {
                    if isTag {
                        Text(icon)
                            .font(.system(size: 16, weight: .bold, design: AppTheme.Layout.fontDesign))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                    }
                }
                .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.5))
                .frame(width: 20)
                
                // Title
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Count (if available)
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: AppTheme.Layout.fontDesign))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(isSelected ? accentColor : accentColor.opacity(0.1))
                        .foregroundStyle(isSelected ? .white : accentColor)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(isSelected ? accentColor.opacity(0.15) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColor.opacity(isSelected ? 0.12 : 0), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
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

private struct SidebarSectionLabel: View {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
