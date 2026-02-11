//
//  TagSidebarView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

/// 左侧滑出标签筛选菜单
struct TagSidebarView: View {
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Binding var selectedTag: Tag?
    @Binding var isOpen: Bool
    @State private var showSettings = false

    private let sidebarWidth: CGFloat = 280

    var body: some View {
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
                sidebarContent
                    .background(AppTheme.cardBackground)
                    .ignoresSafeArea() // 修复上下缺口
                    .premiumShadow()
                Spacer()
            }
            .offset(x: isOpen ? 0 : -sidebarWidth)
        }
        .animation(AppTheme.spring, value: isOpen)
        // 关键修复：当关闭时，侧边栏不应拦截主界面的触摸
        .allowsHitTesting(isOpen)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - 侧边栏内容

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部区域
            headerSection

            // 标签列表
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // "全部 MEMO" 按钮
                    SidebarItemView(
                        title: "全部思考",
                        icon: selectedTag == nil ? "tray.full.fill" : "tray.full",
                        isSelected: selectedTag == nil,
                        action: {
                            selectedTag = nil
                            closeSidebar()
                        }
                    )

                    // 标签列表
                    ForEach(allTags) { tag in
                        SidebarItemView(
                            title: tag.name,
                            icon: "#",
                            isTag: true,
                            count: tag.memos.count,
                            isSelected: selectedTag?.persistentModelID == tag.persistentModelID,
                            action: {
                                selectedTag = tag
                                closeSidebar()
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)

            Spacer()

            // 底部工具
            footerSection
        }
        .frame(width: sidebarWidth)
    }

    private func closeSidebar() {
        isOpen = false
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BB Memo")
                .font(.system(size: 28, weight: .bold, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(AppTheme.brandGradient)
            Text("\(allTags.count) 个标签分类")
                .font(.system(size: 11, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, safeAreaInsets.top + 24)
        .padding(.bottom, 12)
    }

    @Environment(\.safeAreaInsets) private var safeAreaInsets

    private var footerSection: some View {
        Button {
            showSettings = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                Text("偏好设置")
                    .font(.system(size: 15, weight: .medium, design: AppTheme.Layout.fontDesign))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.secondary.opacity(0.05))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar Item View Component

struct SidebarItemView: View {
    let title: String
    let icon: String // 可以是 systemName 或 文字符号
    var isTag: Bool = false
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Group {
                    if isTag {
                        Text(icon)
                            .font(.system(size: 18, weight: .bold, design: AppTheme.Layout.fontDesign))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                    }
                }
                .foregroundStyle(isSelected ? AppTheme.brandAccent : Color.secondary.opacity(0.5))
                .frame(width: 24)
                
                // Title
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Count (if available)
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium, design: AppTheme.Layout.fontDesign))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(isSelected ? AppTheme.brandAccent : AppTheme.brandAccent.opacity(0.1))
                        .foregroundStyle(isSelected ? .white : AppTheme.brandAccent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isSelected ? AppTheme.brandAccent.opacity(0.15) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.brandAccent.opacity(isSelected ? 0.1 : 0), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}
