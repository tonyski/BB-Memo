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

/// 设置页面 — 展示 iCloud 同步状态
struct SettingsView: View {
    @EnvironmentObject private var syncDiagnostics: SyncDiagnostics

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var isProcessingImport = false
    @State private var showImportAlert = false
    @State private var importMessage = ""
    @State private var memoCount = 0
    @State private var tagCount = 0

    var body: some View {
        NavigationStack {
            settingsContent
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
        }
    }

    private var settingsContent: some View {
        ZStack {
            Form {
                syncSection
                dataOverviewSection
                importSection
                aboutSection
            }
            .disabled(isProcessingImport)

            if isProcessingImport {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                ProgressView("正在导入…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear(perform: refreshContentCounts)
        .onReceive(AppNotifications.dataChanges) {
            refreshContentCounts()
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

    private var syncSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .foregroundStyle(AppTheme.brandAccent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud 同步")
                    Text(syncSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let syncIssueMessage {
                Text(syncIssueMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("同步")
        } footer: {
            Text("通过 iCloud 在设备间自动同步。")
        }
    }

    private var dataOverviewSection: some View {
        Section("数据概览") {
            LabeledContent("笔记", value: "\(memoCount)")
            LabeledContent("标签", value: "\(tagCount)")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("从 flomo 导入", systemImage: "square.and.arrow.down")
            }
            .disabled(isProcessingImport)
        } header: {
            Text("导入")
        } footer: {
            Text("支持 flomo HTML 备份，自动跳过重复内容。")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("BB Memo") {
                Text("版本 \(appVersion)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("关于")
        } footer: {
            Text("简单记录，随时回顾。")
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
            let summary = try await FlomoImportService.importFromFile(
                at: url,
                modelContainer: modelContext.container
            )
            didImportSucceed = true
            if summary.parsedCount == 0 {
                importMessage = "未在文件中找到可识别的 flomo 笔记"
            } else if summary.importedCount == 0 {
                importMessage = "文件中的 \(summary.duplicateCount) 条笔记均已存在，无需重复导入"
            } else if summary.duplicateCount > 0 {
                importMessage = "已导入 \(summary.importedCount) 条笔记，跳过 \(summary.duplicateCount) 条重复内容"
            } else {
                importMessage = "已导入 \(summary.importedCount) 条笔记"
            }
        } catch {
            importMessage = "导入失败，请稍后再试。"
        }
        if didImportSucceed {
            AppNotifications.postMemoDataChanged()
        }
        showImportAlert = true
    }

    private func refreshContentCounts() {
        memoCount = fetchCount(FetchDescriptor<Memo>())
        tagCount = fetchCount(FetchDescriptor<Tag>())
    }

    private func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - 同步状态映射

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var syncSubtitle: String {
        guard let date = syncDiagnostics.lastCloudSyncDate else {
            return syncStatusLabel
        }
        let relativeDate = date.formatted(
            .relative(presentation: .named).locale(.autoupdatingCurrent)
        )
        return "\(syncStatusLabel) · \(relativeDate)"
    }

    private var syncStatusLabel: String {
        switch syncDiagnostics.storageMode {
        case .cloudKit:
            return syncDiagnostics.accountStatus == .available
                ? syncDiagnostics.syncState.label
                : accountStatusLabel
        case .inMemoryFallback:
            return syncDiagnostics.storageMode.label
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
            return syncDiagnostics.accountStatusMessage == nil ? "正在检查" : "检查失败"
        @unknown default:
            return "未知状态"
        }
    }

    private var syncIssueMessage: String? {
        if syncDiagnostics.storageMode != .cloudKit {
            return "iCloud 存储无法初始化，请重新启动应用。"
        }
        if syncDiagnostics.accountStatus == .couldNotDetermine,
           syncDiagnostics.accountStatusMessage == nil {
            return nil
        }
        if syncDiagnostics.accountStatus != .available {
            return "当前无法跨设备同步，请确认已登录 iCloud，并允许 BB Memo 使用 iCloud。"
        }
        if case .failed(let errorMessage) = syncDiagnostics.syncState {
            return "同步失败：\(errorMessage)"
        }
        return nil
    }
}
