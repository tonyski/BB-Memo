//
//  SyncDiagnostics.swift
//  BB-Memo
//

import Foundation
import CloudKit
import SwiftData
import Combine
import CoreData

enum SyncLogLevel: String {
    case info
    case success
    case warning
    case error
}

struct SyncLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: SyncLogLevel
    let message: String
}

enum AppStorageMode: Equatable {
    case cloudKit
    case localFallback
    case inMemoryFallback

    var label: String {
        switch self {
        case .cloudKit:
            return "CloudKit（可同步）"
        case .localFallback:
            return "本地数据库（未同步）"
        case .inMemoryFallback:
            return "内存数据库（临时）"
        }
    }
}

struct AppContainerBootstrap {
    let container: ModelContainer
    let storageMode: AppStorageMode
    let startupMessage: String?
}

enum AppContainerFactory {
    static let iCloudContainerIdentifier = "iCloud.com.tonyski.BB-Memo"

    static func make() -> AppContainerBootstrap {
        let schema = Schema([
            Memo.self,
            Tag.self,
        ])
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        let inMemoryConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            return AppContainerBootstrap(container: container, storageMode: .cloudKit, startupMessage: nil)
        } catch let cloudError {
            let cloudErrorMessage = "CloudKit 初始化失败：\(cloudError.localizedDescription)"
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                return AppContainerBootstrap(
                    container: container,
                    storageMode: .localFallback,
                    startupMessage: cloudErrorMessage
                )
            } catch let localError {
                return makeInMemoryBootstrap(
                    schema: schema,
                    inMemoryConfiguration: inMemoryConfiguration,
                    startupMessage: "\(cloudErrorMessage)；本地失败：\(localError.localizedDescription)。已保留本地数据库文件，未执行自动清理。",
                    cloudError: cloudError,
                    localError: localError
                )
            }
        }
    }

    private static func makeInMemoryBootstrap(
        schema: Schema,
        inMemoryConfiguration: ModelConfiguration,
        startupMessage: String,
        cloudError: Error,
        localError: Error,
        retryError: Error? = nil
    ) -> AppContainerBootstrap {
        do {
            let container = try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            return AppContainerBootstrap(
                container: container,
                storageMode: .inMemoryFallback,
                startupMessage: startupMessage
            )
        } catch {
            let retryPart = retryError.map { ", retryError=\($0)" } ?? ""
            fatalError(
                "Could not create ModelContainer. cloudError=\(cloudError), localError=\(localError)\(retryPart), inMemoryError=\(error)"
            )
        }
    }
}

@MainActor
final class SyncDiagnostics: ObservableObject {
    let iCloudContainerIdentifier: String

    @Published private(set) var storageMode: AppStorageMode
    @Published private(set) var startupMessage: String?
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var lastStatusCheckDate: Date?
    @Published private(set) var accountStatusMessage: String?
    @Published private(set) var isManualSyncInProgress = false
    @Published private(set) var lastManualSyncDate: Date?
    @Published private(set) var syncLogs: [SyncLogEntry] = []

    private var cancellables = Set<AnyCancellable>()
    private let maxLogCount = 120

    init(iCloudContainerIdentifier: String, storageMode: AppStorageMode, startupMessage: String?) {
        self.iCloudContainerIdentifier = iCloudContainerIdentifier
        self.storageMode = storageMode
        self.startupMessage = startupMessage
        appendLog(level: .info, "同步诊断已启动，当前模式：\(storageMode.label)")
        if let startupMessage, !startupMessage.isEmpty {
            appendLog(level: .warning, startupMessage)
        }
        observeSyncSignals()
    }

    var syncSummary: String {
        switch storageMode {
        case .cloudKit:
            if accountStatus == .available {
                return "CloudKit 运行正常，数据会后台同步"
            }
            return "CloudKit 已启用，但当前账号状态阻塞同步"
        case .localFallback:
            return "当前使用本地数据库，卸载 App 会丢失本地数据"
        case .inMemoryFallback:
            return "当前使用临时内存数据库，退出 App 即丢失"
        }
    }

    func refreshAccountStatus() async {
        lastStatusCheckDate = .now
        appendLog(level: .info, "开始检查 iCloud 账号状态")
        do {
            let container = CKContainer(identifier: iCloudContainerIdentifier)
            let status = try await container.accountStatus()
            accountStatus = status
            accountStatusMessage = nil
            appendLog(level: status == .available ? .success : .warning, "账号状态：\(accountStatusLabel(status))")
        } catch {
            accountStatus = .couldNotDetermine
            accountStatusMessage = error.localizedDescription
            appendLog(level: .error, "账号状态检查失败：\(error.localizedDescription)")
        }
    }

    func triggerManualSync(using context: ModelContext) async {
        guard !isManualSyncInProgress else {
            appendLog(level: .warning, "已有手动同步任务正在进行")
            return
        }

        syncLogs.removeAll()
        isManualSyncInProgress = true
        appendLog(level: .info, "开始手动同步：检查账号并提交本地事务")
        defer {
            isManualSyncInProgress = false
            lastManualSyncDate = .now
        }

        await refreshAccountStatus()

        guard storageMode == .cloudKit else {
            appendLog(level: .warning, "当前不是 CloudKit 模式，无法执行跨设备同步")
            return
        }
        guard accountStatus == .available else {
            appendLog(level: .warning, "iCloud 账号不可用，已跳过手动同步")
            return
        }

        do {
            try context.save()
            appendLog(level: .success, "本地事务提交成功，CloudKit 将在后台同步")
        } catch {
            appendLog(level: .error, "本地事务提交失败：\(error.localizedDescription)")
        }
    }

    private func observeSyncSignals() {
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appendLog(level: .info, "检测到远端数据变更通知")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .memoDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appendLog(level: .info, "检测到本地数据变更")
            }
            .store(in: &cancellables)
    }

    private func appendLog(level: SyncLogLevel, _ message: String) {
        syncLogs.append(SyncLogEntry(date: .now, level: level, message: message))
        if syncLogs.count > maxLogCount {
            syncLogs.removeFirst(syncLogs.count - maxLogCount)
        }
    }

    private func accountStatusLabel(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "可用"
        case .noAccount: return "未登录 iCloud"
        case .restricted: return "受限制"
        case .temporarilyUnavailable: return "暂时不可用"
        case .couldNotDetermine: return "无法判断"
        @unknown default: return "未知状态"
        }
    }
}
