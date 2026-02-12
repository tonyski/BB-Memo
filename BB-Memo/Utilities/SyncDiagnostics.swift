//
//  SyncDiagnostics.swift
//  BB-Memo
//

import Foundation
import CloudKit
import SwiftData
import Combine

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
                // 模型变更导致旧数据不兼容时，清除旧数据重试（本地配置）
                let url = localConfiguration.url
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
                do {
                    let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                    return AppContainerBootstrap(
                        container: container,
                        storageMode: .localFallback,
                        startupMessage: "\(cloudErrorMessage)；本地恢复：\(localError.localizedDescription)"
                    )
                } catch let retryError {
                    do {
                        let container = try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
                        return AppContainerBootstrap(
                            container: container,
                            storageMode: .inMemoryFallback,
                            startupMessage: "\(cloudErrorMessage)；本地失败：\(retryError.localizedDescription)"
                        )
                    } catch {
                        fatalError(
                            "Could not create ModelContainer. cloudError=\(cloudError), localError=\(localError), retryError=\(retryError), inMemoryError=\(error)"
                        )
                    }
                }
            }
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

    init(iCloudContainerIdentifier: String, storageMode: AppStorageMode, startupMessage: String?) {
        self.iCloudContainerIdentifier = iCloudContainerIdentifier
        self.storageMode = storageMode
        self.startupMessage = startupMessage
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
        do {
            let container = CKContainer(identifier: iCloudContainerIdentifier)
            let status = try await container.accountStatus()
            accountStatus = status
            accountStatusMessage = nil
        } catch {
            accountStatus = .couldNotDetermine
            accountStatusMessage = error.localizedDescription
        }
    }
}
