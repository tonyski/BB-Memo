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
    @State private var lastSyncDate: Date?

    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var showImportAlert = false
    @State private var importMessage = ""

    enum SyncStatus: Equatable {
        case checking
        case synced
        case syncing
        case error(String)
        case notAvailable

        var label: String {
            switch self {
            case .checking: return "检查中..."
            case .synced: return "已同步"
            case .syncing: return "同步中..."
            case .error(let msg): return "同步异常：\(msg)"
            case .notAvailable: return "iCloud 不可用"
            }
        }

        var icon: String {
            switch self {
            case .checking: return "arrow.triangle.2.circlepath"
            case .synced: return "checkmark.icloud"
            case .syncing: return "arrow.triangle.2.circlepath.icloud"
            case .error: return "exclamationmark.icloud"
            case .notAvailable: return "icloud.slash"
            }
        }

        var color: Color {
            switch self {
            case .checking: return .gray
            case .synced: return .green
            case .syncing: return .orange
            case .error: return .red
            case .notAvailable: return .red
            }
        }
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
                    if let date = lastSyncDate {
                        Text("上次同步：\(date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    Image(systemName: "square.and.arrow.down.on.square")
                        .foregroundStyle(AppTheme.brandAccent)
                    Text("从 flomo 迁移 (.html)")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
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
        Task { await performImport(from: url) }
    }

    private func performImport(from url: URL) async {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.permissionDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let html = try String(contentsOf: url, encoding: .utf8)
            let flomoMemos = FlomoImporter.parse(html: html)

            for fMemo in flomoMemos {
                let tagNames = TagExtractor.extractHashtags(from: fMemo.content)
                let tags = try resolveTagsForImport(tagNames)
                modelContext.insert(Memo(
                    content: fMemo.content,
                    createdAt: fMemo.createdAt,
                    updatedAt: fMemo.createdAt,
                    tags: tags
                ))
                TagUsageCounter.increment(tags)
            }

            try modelContext.save()
            importMessage = flomoMemos.isEmpty
                ? "未在文件中找到可识别的 flomo 记录"
                : "已成功迁移 \(flomoMemos.count) 条思考到 BB Memo"
        } catch {
            importMessage = "导入失败: \(error.localizedDescription)"
        }
        showImportAlert = true
    }

    private func resolveTagsForImport(_ names: [String]) throws -> [Tag] {
        var results: [Tag] = []
        for name in names {
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate<Tag> { $0.name == name })
            if let existing = try modelContext.fetch(descriptor).first {
                results.append(existing)
            } else {
                let newTag = Tag(name: name)
                modelContext.insert(newTag)
                results.append(newTag)
            }
        }
        return results
    }
    
    enum ImportError: LocalizedError {
        case permissionDenied
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "无法获取文件访问权限"
            }
        }
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

        // 通过 ubiquityIdentityToken 检测 iCloud 账户可用性
        if FileManager.default.ubiquityIdentityToken != nil {
            syncStatus = .synced
            lastSyncDate = Date.now
        } else {
            syncStatus = .notAvailable
        }
    }
}
