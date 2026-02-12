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
    @Query(
        sort: [
            SortDescriptor(\Tag.usageCount, order: .reverse),
            SortDescriptor(\Tag.name, order: .forward)
        ]
    ) private var allTags: [Tag]
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
            SettingsSheetView()
        }
    }

    // MARK: - 侧边栏内容

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部区域
            headerSection

            Divider()

            // 固定滚动区域，仅中间列表滚动
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    SidebarItemView(
                        title: "全部思考",
                        icon: selectedTag == nil ? "tray.full.fill" : "tray.full",
                        isSelected: selectedTag == nil,
                        action: {
                            selectedTag = nil
                            closeSidebar()
                        }
                    )

                    ForEach(allTags) { tag in
                        SidebarItemView(
                            title: tag.name,
                            icon: "#",
                            isTag: true,
                            count: tag.usageCount,
                            isSelected: selectedTag?.persistentModelID == tag.persistentModelID,
                            action: {
                                selectedTag = tag
                                closeSidebar()
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .scrollIndicators(.hidden)
        }
        .frame(width: sidebarWidth)
    }

    private func closeSidebar() {
        withAnimation(AppTheme.spring) {
            isOpen = false
        }
        HapticFeedback.selection.play()
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BB Memo")
                    .font(.system(size: 28, weight: .bold, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(AppTheme.brandGradient)
                Text("\(allTags.count) 个标签分类")
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
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, safeAreaInsets.top + 24)
        .padding(.bottom, 10)
    }

    @Environment(\.safeAreaInsets) private var safeAreaInsets
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
                .foregroundStyle(isSelected ? AppTheme.brandAccent : Color.secondary.opacity(0.5))
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
                        .background(isSelected ? AppTheme.brandAccent : AppTheme.brandAccent.opacity(0.1))
                        .foregroundStyle(isSelected ? .white : AppTheme.brandAccent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(isSelected ? AppTheme.brandAccent.opacity(0.15) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.brandAccent.opacity(isSelected ? 0.1 : 0), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}
