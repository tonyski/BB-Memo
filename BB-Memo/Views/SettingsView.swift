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
        .onReceive(NotificationCenter.default.publisher(for: .memoDataChanged)) { _ in
            refreshDataOverview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
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
                    panelTitle("同步中心", icon: "icloud")
                    Spacer()
                    Button {
                        Task { await syncDiagnostics.triggerManualSync(using: modelContext) }
                    } label: {
                        if syncDiagnostics.isManualSyncInProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(syncDiagnostics.isManualSyncInProgress ? .secondary : AppTheme.brandAccent)
                    .disabled(syncDiagnostics.isManualSyncInProgress)
                }

                LazyVGrid(columns: syncInsightColumns, spacing: 8) {
                    insightTile(title: "存储模式", value: syncDiagnostics.storageMode.label)
                    insightTile(title: "账号状态", value: accountStatusLabel)
                    insightTile(
                        title: "最近检查",
                        value: syncDiagnostics.lastStatusCheckDate?.formatted(.relative(presentation: .named)) ?? "未检查"
                    )
                    insightTile(title: "最近手动同步", value: syncDiagnostics.lastManualSyncDate?.formatted(.relative(presentation: .named)) ?? "未执行")
                }

                if !diagnosticMessages.isEmpty {
                    DisclosureGroup("诊断详情") {
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
                                        Text("\(entry.date.formatted(.dateTime.hour().minute().second())) [\(syncLogLevelLabel(entry.level))] \(entry.message)")
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
                            Text("同步日志")
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
                panelTitle("数据概览", icon: "chart.bar")

                HStack(spacing: 8) {
                    metricTile(icon: "doc.text", label: "Memo", value: "\(memoCount)")
                    metricTile(icon: "tag", label: "标签", value: "\(tagCount)")
                    metricTile(icon: "bell", label: "提醒", value: "\(remindersCount)")
                }

                if let lastLocalUpdateDate {
                    Text("最近更新：\(lastLocalUpdateDate.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dataManagementPanel: some View {
        panelContainer {
            VStack(alignment: .leading, spacing: 8) {
                panelTitle("数据管理", icon: "square.and.arrow.down")

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

                        Text(isProcessingImport ? "正在导入 flomo..." : "从 flomo 导入 (.html)")
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
                panelTitle("应用信息", icon: "info.circle")
                infoRow(label: "版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
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
            if case .failure(let error) = result {
                importMessage = "文件选择失败: \(error.localizedDescription)"
                showImportAlert = true
            }
            return
        }
        isProcessingImport = true
        Task { await performImport(from: url) }
    }

    private func performImport(from url: URL) async {
        defer { isProcessingImport = false }
        do {
            let summary = try await FlomoImportService.importFromFile(at: url, context: modelContext)
            importMessage = summary.importedCount == 0
                ? "未在文件中找到可识别的 flomo 记录"
                : "已成功迁移 \(summary.importedCount) 条思考到 BB Memo"
        } catch {
            importMessage = "导入失败: \(error.localizedDescription)"
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
            return "可用"
        case .noAccount:
            return "未登录 iCloud"
        case .restricted:
            return "受限制"
        case .temporarilyUnavailable:
            return "暂时不可用"
        case .couldNotDetermine:
            return "无法判断"
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
            messages.append("仅当存储模式为 CloudKit 且账号可用时，数据才会跨设备同步。")
        }
        if let startupMessage = syncDiagnostics.startupMessage, !startupMessage.isEmpty {
            messages.append(startupMessage)
        }
        if let accountStatusMessage = syncDiagnostics.accountStatusMessage, !accountStatusMessage.isEmpty {
            messages.append("账号检查失败：\(accountStatusMessage)")
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
