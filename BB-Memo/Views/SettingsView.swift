//
//  SettingsView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit
import CoreData
import Combine

/// 设置页面 — 展示 iCloud 同步状态
struct SettingsView: View {
    @EnvironmentObject private var syncDiagnostics: SyncDiagnostics

    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var isProcessingImport = false
    @State private var showImportAlert = false
    @State private var importMessage = ""
    @State private var memoCount = 0
    @State private var tagCount = 0
    @State private var remindersCount = 0
    @State private var lastLocalUpdateDate: Date?
    @State private var isSyncLogExpanded = false

    private let syncInsightColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        #if os(macOS)
        settingsContent
            .frame(minWidth: 420, minHeight: 520)
        #else
        NavigationStack {
            settingsContent
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
        }
        #endif
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                syncPanel
                dataOverviewPanel
                dataManagementPanel
                appInfoPanel
            }
            .padding(12)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .overlay {
            if isProcessingImport {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("导入中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .transition(.opacity)
            }
        }
        .task {
            await syncDiagnostics.refreshAccountStatus()
            refreshDataOverview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoDataChanged).receive(on: RunLoop.main)) { _ in
            refreshDataOverview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            refreshDataOverview()
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.html],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("导入结果", isPresented: $showImportAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(importMessage)
        }
    }

    // MARK: - 新布局

    private var syncPanel: some View {
        panelContainer(borderColor: syncIndicatorColor.opacity(0.28)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    panelTitle("云端同步", icon: "icloud")
                    Spacer()
                    Button {
                        Task { await syncDiagnostics.triggerManualSync(using: modelContext) }
                    } label: {
                        if syncDiagnostics.isManualSyncInProgress {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("同步中")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("立即同步")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(syncDiagnostics.isManualSyncInProgress ? .secondary : AppTheme.brandAccent)
                    .disabled(syncDiagnostics.isManualSyncInProgress)
                    .accessibilityLabel("立即同步")
                    .accessibilityHint("马上检查账号并尝试同步到云端")
                }

                LazyVGrid(columns: syncInsightColumns, spacing: 8) {
                    insightTile(title: "同步方式", value: syncDiagnostics.storageMode.label)
                    insightTile(title: "账号连接", value: accountStatusLabel)
                    insightTile(
                        title: "上次检查",
                        value: syncDiagnostics.lastStatusCheckDate?.formatted(
                            .relative(presentation: .named).locale(.autoupdatingCurrent)
                        ) ?? "未检查"
                    )
                    insightTile(
                        title: "上次同步",
                        value: syncDiagnostics.lastManualSyncDate?.formatted(
                            .relative(presentation: .named).locale(.autoupdatingCurrent)
                        ) ?? "未执行"
                    )
                }

                Text(syncDiagnostics.syncSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !diagnosticMessages.isEmpty {
                    DisclosureGroup("同步说明") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(diagnosticMessages.enumerated()), id: \.offset) { _, message in
                                Text("• \(message)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption2)
                    .tint(.secondary)
                }

                if !syncDiagnostics.syncLogs.isEmpty {
                    DisclosureGroup(
                        isExpanded: $isSyncLogExpanded,
                        content: {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(syncDiagnostics.syncLogs.reversed()) { entry in
                                        Text(
                                            "\(entry.date.formatted(.dateTime.hour().minute().second().locale(.autoupdatingCurrent))) [\(syncLogLevelLabel(entry.level))] \(entry.message)"
                                        )
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                            .padding(.top, 4)
                        },
                        label: {
                            Text("同步记录（高级）")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    )
                    .tint(.secondary)
                }
            }
        }
    }

    private var dataOverviewPanel: some View {
        panelContainer {
            VStack(alignment: .leading, spacing: 10) {
                panelTitle("你的数据", icon: "chart.bar")

                HStack(spacing: 8) {
                    metricTile(icon: "doc.text", label: "笔记", value: "\(memoCount)")
                    metricTile(icon: "tag", label: "标签", value: "\(tagCount)")
                    metricTile(icon: "bell", label: "提醒", value: "\(remindersCount)")
                }

                if let lastLocalUpdateDate {
                    Text(
                        "最近一次修改：\(lastLocalUpdateDate.formatted(.relative(presentation: .named).locale(.autoupdatingCurrent)))"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dataManagementPanel: some View {
        panelContainer {
            VStack(alignment: .leading, spacing: 8) {
                panelTitle("导入与备份", icon: "square.and.arrow.down")

                Button {
                    isImporting = true
                } label: {
                    HStack(spacing: 8) {
                        Group {
                            if isProcessingImport {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.down.on.square")
                            }
                        }
                        .foregroundStyle(AppTheme.brandAccent)

                        Text(isProcessingImport ? "正在导入 flomo..." : "导入 flomo 备份（HTML 文件）")
                            .font(.footnote)
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.brandAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isProcessingImport)
            }
        }
    }

    private var appInfoPanel: some View {
        panelContainer {
            VStack(alignment: .leading, spacing: 8) {
                panelTitle("关于 BB Memo", icon: "info.circle")
                infoRow(label: "当前版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
    }

    // MARK: - 组件

    private func panelContainer<Content: View>(
        borderColor: Color = .primary.opacity(0.06),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func panelTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.brandAccent)
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    private func insightTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metricTile(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.brandAccent.opacity(0.75))
            Text(value)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.brandAccent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote)
                .fontWeight(.medium)
        }
    }

    // MARK: - 导入

    private func handleImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result {
                importMessage = "没有成功选择文件，请重试。"
                showImportAlert = true
            }
            return
        }
        isProcessingImport = true
        Task { await performImport(from: url) }
    }

    private func performImport(from url: URL) async {
        defer { isProcessingImport = false }
        var didImportSucceed = false
        do {
            let summary = try await FlomoImportService.importFromFile(at: url, context: modelContext)
            didImportSucceed = true
            importMessage = summary.importedCount == 0
                ? "未在文件中找到可识别的 flomo 笔记"
                : "已导入 \(summary.importedCount) 条笔记"
        } catch {
            importMessage = "导入失败，请稍后再试。"
        }
        if didImportSucceed {
            AppNotifications.postMemoDataChanged()
        }
        refreshDataOverview()
        showImportAlert = true
    }

    private func refreshDataOverview() {
        memoCount = fetchCount(FetchDescriptor<Memo>())
        tagCount = fetchCount(FetchDescriptor<Tag>())
        remindersCount = fetchCount(
            FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { memo in
                    memo.reminderDate != nil
                }
            )
        )

        var latestDescriptor = FetchDescriptor<Memo>(
            sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1
        lastLocalUpdateDate = (try? modelContext.fetch(latestDescriptor).first?.updatedAt) ?? nil
    }

    private func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - 同步状态映射

    private var syncIndicatorColor: Color {
        switch syncDiagnostics.storageMode {
        case .cloudKit:
            return syncDiagnostics.accountStatus == .available ? .green : .orange
        case .localFallback, .inMemoryFallback:
            return .red
        }
    }

    private var accountStatusLabel: String {
        switch syncDiagnostics.accountStatus {
        case .available:
            return "已连接"
        case .noAccount:
            return "未登录 iCloud"
        case .restricted:
            return "系统限制"
        case .temporarilyUnavailable:
            return "服务暂不可用"
        case .couldNotDetermine:
            return "检查失败"
        @unknown default:
            return "未知状态"
        }
    }

    private var isSyncHealthy: Bool {
        syncDiagnostics.storageMode == .cloudKit && syncDiagnostics.accountStatus == .available
    }

    private var diagnosticMessages: [String] {
        var messages: [String] = []
        if !isSyncHealthy {
            messages.append("当前无法跨设备同步，请先确认已登录 iCloud，并允许 BB Memo 使用 iCloud。")
        }
        if let startupMessage = syncDiagnostics.startupMessage, !startupMessage.isEmpty {
            switch syncDiagnostics.storageMode {
            case .cloudKit:
                messages.append("云同步已恢复，你的数据会继续自动同步。")
            case .localFallback:
                messages.append("云同步暂时不可用，应用已切换为本机保存。")
            case .inMemoryFallback:
                messages.append("当前处于临时模式，请稍后重启应用再试。")
            }
        }
        if let accountStatusMessage = syncDiagnostics.accountStatusMessage, !accountStatusMessage.isEmpty {
            messages.append("当前无法获取 iCloud 状态，请稍后再试。")
        }
        return messages
    }

    private func syncLogLevelLabel(_ level: SyncLogLevel) -> String {
        switch level {
        case .info: return "INFO"
        case .success: return "OK"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}
