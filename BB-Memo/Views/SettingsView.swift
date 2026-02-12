//
//  SettingsView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 设置页面 — 展示 iCloud 同步状态
struct SettingsView: View {
    @Query private var memos: [Memo]
    @Query private var tags: [Tag]

    @State private var syncStatus: SyncStatus = .checking
    @State private var lastStatusCheckDate: Date?

    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var isProcessingImport = false
    @State private var showImportAlert = false
    @State private var importMessage = ""

    enum SyncStatus: Equatable {
        case checking
        case available
        case notAvailable

        var label: String {
            switch self {
            case .checking: return "检查中..."
            case .available: return "iCloud 可用"
            case .notAvailable: return "iCloud 不可用"
            }
        }

        var icon: String {
            switch self {
            case .checking: return "arrow.triangle.2.circlepath"
            case .available: return "checkmark.icloud"
            case .notAvailable: return "icloud.slash"
            }
        }

        var color: Color {
            switch self {
            case .checking: return .gray
            case .available: return .green
            case .notAvailable: return .red
            }
        }
    }

    private var lastLocalUpdateDate: Date? {
        memos.map(\.updatedAt).max()
    }

    var body: some View {
        #if os(macOS)
        settingsContent
            .frame(minWidth: 380, minHeight: 420)
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
            VStack(spacing: 16) {
                // iCloud 同步状态卡片
                syncStatusCard

                // 数据统计卡片
                dataStatsCard

                // 数据管理
                dataManagementCard

                // 关于
                aboutCard
            }
            .padding(20)
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
        .onAppear { checkiCloudStatus() }
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

    // MARK: - iCloud 同步状态

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "icloud")
                    .font(.title3)
                    .foregroundStyle(AppTheme.brandAccent)
                Text("iCloud 同步")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Divider()

            HStack(spacing: 12) {
                // 状态指示灯
                ZStack {
                    Circle()
                        .fill(syncStatus.color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: syncStatus.icon)
                        .font(.body)
                        .foregroundStyle(syncStatus.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(syncStatus.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if syncStatus == .available {
                        Text("CloudKit 已启用，数据后台异步同步")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let date = lastLocalUpdateDate {
                        Text("最近本地更新：\(date.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let date = lastStatusCheckDate {
                        Text("状态检查：\(date.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // 刷新按钮
                Button {
                    checkiCloudStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.brandAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .memoCardStyle(cornerRadius: 12)
    }

    // MARK: - 数据统计

    private var dataStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar")
                    .font(.title3)
                    .foregroundStyle(AppTheme.brandAccent)
                Text("数据统计")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Divider()

            HStack(spacing: 0) {
                statItem(icon: "doc.text", label: "MEMO", value: "\(memos.count)")
                Spacer()
                statItem(icon: "tag", label: "标签", value: "\(tags.count)")
                Spacer()
                statItem(icon: "pin", label: "置顶", value: "\(memos.filter(\.isPinned).count)")
            }
        }
        .padding(16)
        .memoCardStyle(cornerRadius: 12)
    }

    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.brandAccent.opacity(0.7))
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.brandAccent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 数据管理

    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(AppTheme.brandAccent)
                Text("数据管理")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Divider()

            Button {
                isImporting = true
            } label: {
                HStack {
                    if isProcessingImport {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .foregroundStyle(AppTheme.brandAccent)
                    }
                    Text(isProcessingImport ? "正在导入..." : "从 flomo 迁移 (.html)")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(isProcessingImport)
        }
        .padding(16)
        .memoCardStyle(cornerRadius: 12)
    }

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
        showImportAlert = true
    }

    // MARK: - 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.brandAccent)
                Text("关于")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Divider()

            VStack(spacing: 8) {
                infoRow(label: "版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                infoRow(label: "构建", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }
        }
        .padding(16)
        .memoCardStyle(cornerRadius: 12)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - iCloud 检测

    private func checkiCloudStatus() {
        syncStatus = .checking
        lastStatusCheckDate = .now

        // 通过 ubiquityIdentityToken 检测 iCloud 账户可用性
        if FileManager.default.ubiquityIdentityToken != nil {
            syncStatus = .available
        } else {
            syncStatus = .notAvailable
        }
    }
}
