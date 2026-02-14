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
    
    private var memoMenu: some View {
        Menu {
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
                Button { onEdit?() } label: {
                    Label("编辑", systemImage: "pencil")
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
                    presentDeleteAlert(.recycle)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.brandAccent.opacity(0.6))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: memo.isPinned)
        .accessibilityLabel("更多操作")
        .accessibilityHint("编辑、置顶或删除这条笔记")
    }

    private func moveToRecycleBin() {
        let reminderID = memo.reminderIdentifier
        withAnimation(AppTheme.spring) {
            do {
                try MemoMutationService.deleteMemo(memo, context: modelContext)
                onMemoRemoved?(memo.stableID)
                NotificationManager.cancelReminder(memoID: reminderID)
                AppNotifications.postMemoDataChanged()
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
        if !memo.tagsList.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(memo.tagsList) { tag in
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
