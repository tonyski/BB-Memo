//
//  MemoCardView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import UIKit

/// 单条 Memo — 带 dropdown 菜单
struct MemoCardView: View {
    enum Mode {
        case normal
        case recycleBin
    }

    private enum PendingDeleteAction {
        case recycle
        case permanent

        var title: String {
            switch self {
            case .recycle: return "移入回收站？"
            case .permanent: return "彻底删除？"
            }
        }

        var confirmTitle: String {
            switch self {
            case .recycle: return "移入回收站"
            case .permanent: return "彻底删除"
            }
        }

        var message: String {
            switch self {
            case .recycle: return "你可以在回收站里恢复这条笔记。"
            case .permanent: return "彻底删除后将无法恢复。"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    let memo: Memo
    var mode: Mode = .normal
    var onEdit: (() -> Void)?
    var onTagTap: ((Tag) -> Void)?
    var onMemoRemoved: ((UUID) -> Void)?
    /// 提供时，「删除」直接移入回收站不再弹确认，由调用方展示「撤销」。
    /// 参数为笔记及其删除前的提醒时间（移入回收站会清空提醒）。
    var onMovedToRecycleBin: ((Memo, Date?) -> Void)?

    @State private var isExpanded = false
    @State private var pendingDeleteAction: PendingDeleteAction?
    @State private var isDeleteAlertPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerRow
            contentSection
            tagsRow
                .padding(.top, 3)
        }
        .padding(.bottom, 3)
        .padding(.horizontal, AppTheme.Layout.cardPadding)
        .memoCardStyle()
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: AppTheme.Layout.cornerRadius)
        )
        .contextMenu { menuItems }
        .sensoryFeedback(.impact, trigger: isExpanded)
        .alert(
            pendingDeleteAction?.title ?? "",
            isPresented: $isDeleteAlertPresented,
            presenting: pendingDeleteAction
        ) { action in
            Button(action.confirmTitle, role: .destructive) {
                handleDelete(action)
            }
            Button("取消", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .onChange(of: isDeleteAlertPresented) { _, isPresented in
            if !isPresented {
                pendingDeleteAction = nil
            }
        }
    }

    // MARK: - 顶部：日期 + 状态图标 + 菜单

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(
                memo.createdAt,
                format: .dateTime
                    .year()
                    .month()
                    .day()
                    .hour()
                    .minute()
                    .locale(.autoupdatingCurrent)
            )
                .font(.system(size: 11, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.secondary)

            Spacer()

            if memo.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.success)
                    .accessibilityLabel("已置顶")
            }

            if memo.reminderDate != nil {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityLabel("已设置提醒")
            }

            memoMenu
        }
    }
    
    // ... memoMenu ...
    
    @ViewBuilder
    private var menuItems: some View {
        if mode == .recycleBin {
            Button {
                withAnimation(AppTheme.spring) {
                    do {
                        try MemoMutationService.restoreMemo(memo, context: modelContext)
                        onMemoRemoved?(memo.stableID)
                        AppNotifications.postMemoDataChanged()
                    } catch {
                        print("MemoCardView restore failed: \(error)")
                    }
                }
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                presentDeleteAlert(.permanent)
            } label: {
                Label("彻底删除", systemImage: "trash")
            }
        } else {
            if onEdit != nil {
                Button { onEdit?() } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
            Button {
                UIPasteboard.general.string = memo.content
                HapticFeedback.light.play()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            ShareLink(item: memo.content) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Button {
                withAnimation(AppTheme.spring) {
                    do {
                        try MemoMutationService.togglePinned(memo, context: modelContext)
                        AppNotifications.postMemoDataChanged()
                    } catch {
                        print("MemoCardView togglePinned failed: \(error)")
                    }
                }
            } label: {
                Label(
                    memo.isPinned ? "取消置顶" : "置顶",
                    systemImage: memo.isPinned ? "pin.slash" : "pin"
                )
            }
            Divider()
            Button(role: .destructive) {
                if onMovedToRecycleBin != nil {
                    moveToRecycleBin()
                } else {
                    presentDeleteAlert(.recycle)
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var memoMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.brandAccent.opacity(0.6))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: memo.isPinned)
        .accessibilityLabel("更多操作")
        .accessibilityHint("编辑、复制、分享、置顶或删除这条笔记")
    }

    private func moveToRecycleBin() {
        let reminderID = memo.reminderIdentifier
        let previousReminderDate = memo.reminderDate
        withAnimation(AppTheme.spring) {
            do {
                try MemoMutationService.deleteMemo(memo, context: modelContext)
                onMemoRemoved?(memo.stableID)
                NotificationManager.cancelReminder(memoID: reminderID)
                AppNotifications.postMemoDataChanged()
                HapticFeedback.medium.play()
                onMovedToRecycleBin?(memo, previousReminderDate)
            } catch {
                print("MemoCardView moveToRecycleBin failed: \(error)")
            }
        }
    }

    private func presentDeleteAlert(_ action: PendingDeleteAction) {
        pendingDeleteAction = action
        Task { @MainActor in
            isDeleteAlertPresented = true
        }
    }

    private func handleDelete(_ action: PendingDeleteAction) {
        switch action {
        case .recycle:
            moveToRecycleBin()
        case .permanent:
            permanentlyDeleteMemo()
        }
    }

    private func permanentlyDeleteMemo() {
        let reminderID = memo.reminderIdentifier
        withAnimation(AppTheme.spring) {
            do {
                try MemoMutationService.permanentlyDeleteMemo(memo, context: modelContext)
                onMemoRemoved?(memo.stableID)
                NotificationManager.cancelReminder(memoID: reminderID)
                AppNotifications.postMemoDataChanged()
            } catch {
                print("MemoCardView permanentlyDeleteMemo failed: \(error)")
            }
        }
    }

    // MARK: - 内容文本（支持展开/收起）

    @ViewBuilder
    private var contentSection: some View {
        Text(memo.content)
            .font(.system(.body, design: AppTheme.Layout.fontDesign))
            .foregroundStyle(.primary)
            .lineSpacing(6)
            .lineLimit(memo.isLong && !isExpanded ? 6 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit?()
            }
            .accessibilityAddTraits(onEdit == nil ? [] : .isButton)
            .accessibilityHint(onEdit == nil ? "" : "轻点编辑")

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
            .padding(.vertical, 4)
        }
    }

    // MARK: - 底部标签

    @ViewBuilder
    private var tagsRow: some View {
        let tags = memo.tagsList
        if !tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
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
