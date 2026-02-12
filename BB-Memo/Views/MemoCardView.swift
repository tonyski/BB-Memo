//
//  MemoCardView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

/// 单条 Memo — 带 dropdown 菜单
struct MemoCardView: View {
    @Environment(\.modelContext) private var modelContext
    let memo: Memo
    var onEdit: (() -> Void)?
    var onTagTap: ((Tag) -> Void)?

    @State private var isExpanded = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Layout.cardSpacing) {
            headerRow
            contentSection
            tagsRow
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .padding(.horizontal, AppTheme.Layout.cardPadding)
        .sensoryFeedback(.impact, trigger: isExpanded)
        .confirmationDialog("确定删除这条思考？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                withAnimation {
                    TagUsageCounter.decrement(memo.tags)
                    NotificationManager.cancelReminder(
                        memoID: memo.persistentModelID.hashValue.description
                    )
                    modelContext.delete(memo)
                    NotificationCenter.default.post(name: .memoDataChanged, object: nil)
                }
            }
        }
    }

    // MARK: - 顶部：日期 + 状态图标 + 菜单

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(memo.createdAt, style: .relative)
                .font(.system(size: 11, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)
            
            Text("前")
                .font(.system(size: 11, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)

            Spacer()

            if memo.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.success)
            }

            if memo.reminderDate != nil {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
            }

            memoMenu
        }
    }
    
    // ... memoMenu ...
    
    private var memoMenu: some View {
        Menu {
            Button { onEdit?() } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                withAnimation(AppTheme.spring) { memo.isPinned.toggle() }
            } label: {
                Label(
                    memo.isPinned ? "取消置顶" : "置顶",
                    systemImage: memo.isPinned ? "pin.slash" : "pin"
                )
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.brandAccent.opacity(0.6))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: memo.isPinned)
    }

    // MARK: - 内容文本（支持展开/收起）

    @ViewBuilder
    private var contentSection: some View {
        Text(memo.content)
            .font(.system(.body, design: AppTheme.Layout.fontDesign))
            .foregroundStyle(.primary)
            .lineSpacing(6)
            .lineLimit(memo.isLong && !isExpanded ? 6 : nil)

        if memo.isLong {
            Button {
                withAnimation(AppTheme.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "收起" : "展开全文")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(AppTheme.action)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 底部标签

    @ViewBuilder
    private var tagsRow: some View {
        if !memo.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(memo.tags) { tag in
                    let color = AppTheme.tagColor(for: tag.name)
                    Button {
                        onTagTap?(tag)
                    } label: {
                        Text("#\(tag.name)")
                            .font(.system(size: 13, design: AppTheme.Layout.fontDesign))
                            .foregroundStyle(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
        }
    }
}
