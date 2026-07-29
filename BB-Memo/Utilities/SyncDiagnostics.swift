//
//  SyncDiagnostics.swift
//  BB-Memo
//

import Foundation
import CloudKit
import SwiftData
import Combine
import CoreData
import OSLog

enum CloudSyncState: Equatable {
    case disabled
    case idle
    case syncing
    case succeeded
    case failed(String)

    var label: String {
        switch self {
        case .disabled: return "未启用"
        case .idle: return "等待同步"
        case .syncing: return "同步中"
        case .succeeded: return "最近同步成功"
        case .failed: return "同步失败"
        }
    }
}

enum AppStorageMode: Equatable {
    case cloudKit
    case inMemoryFallback

    var label: String {
        switch self {
        case .cloudKit: return "iCloud"
        case .inMemoryFallback: return "存储不可用"
        }
    }
}

struct AppContainerBootstrap {
    let container: ModelContainer
    let storageMode: AppStorageMode
}

enum AppContainerFactory {
    static let iCloudContainerIdentifier = "iCloud.com.tonyski.BB-Memo"
    private static let logger = Logger(
        subsystem: "com.tonyski.BB-Memo",
        category: "PersistentStore"
    )

    static func make() -> AppContainerBootstrap {
        let schema = Schema([Memo.self, Tag.self])
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [cloudConfiguration]
            )
            return AppContainerBootstrap(container: container, storageMode: .cloudKit)
        } catch {
            logger.error(
                "CloudKit store initialization failed: \(errorDetails(error), privacy: .public)"
            )
            return makeUnavailableBootstrap(schema: schema, cloudError: error)
        }
    }

    private static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        var details = "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            details += " | underlying: \(errorDetails(underlyingError))"
        }
        return details
    }

    private static func makeUnavailableBootstrap(
        schema: Schema,
        cloudError: Error
    ) -> AppContainerBootstrap {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            return AppContainerBootstrap(
                container: container,
                storageMode: .inMemoryFallback
            )
        } catch {
            fatalError(
                "Could not create ModelContainer. cloudError=\(cloudError), inMemoryError=\(error)"
            )
        }
    }
}

@MainActor
final class SyncDiagnostics: ObservableObject {
    let iCloudContainerIdentifier: String
    let storageMode: AppStorageMode

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var accountStatusMessage: String?
    @Published private(set) var syncState: CloudSyncState
    @Published private(set) var lastCloudSyncDate: Date?

    private var cancellables = Set<AnyCancellable>()
    private var activeCloudEvents = Set<UUID>()
    private var currentBatchFailure: String?
    private var batchHasDataTransfer = false
    private var cloudRefreshTask: Task<Void, Never>?
    private let lastSuccessfulTransferKey: String

    init(iCloudContainerIdentifier: String, storageMode: AppStorageMode) {
        let transferKey =
            "cloudSync.lastSuccessfulTransfer.\(iCloudContainerIdentifier)"
        let persistedTransferDate = UserDefaults.standard.object(
            forKey: transferKey
        ) as? Date

        self.iCloudContainerIdentifier = iCloudContainerIdentifier
        self.storageMode = storageMode
        self.syncState = storageMode == .cloudKit
            ? (persistedTransferDate == nil ? .idle : .succeeded)
            : .disabled
        self.lastSuccessfulTransferKey = transferKey
        self.lastCloudSyncDate = persistedTransferDate

        if storageMode == .cloudKit {
            observeSyncSignals()
        }
    }

    func refreshAccountStatus() async {
        guard storageMode == .cloudKit else {
            accountStatus = .couldNotDetermine
            accountStatusMessage = "iCloud 存储未启用"
            return
        }

        do {
            accountStatus = try await CKContainer(
                identifier: iCloudContainerIdentifier
            ).accountStatus()
            accountStatusMessage = nil
        } catch {
            accountStatus = .couldNotDetermine
            accountStatusMessage = error.localizedDescription
        }
    }

    private func observeSyncSignals() {
        NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            self?.handleCloudKitEvent(notification)
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleCloudDataRefresh()
            }
            .store(in: &cancellables)
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        let isDataTransfer = event.type == .import || event.type == .export
        guard event.endDate != nil else {
            if activeCloudEvents.isEmpty {
                currentBatchFailure = nil
                batchHasDataTransfer = false
            }
            activeCloudEvents.insert(event.identifier)
            batchHasDataTransfer = batchHasDataTransfer || isDataTransfer
            syncState = .syncing
            return
        }

        let wasTracked = activeCloudEvents.remove(event.identifier) != nil
        if !wasTracked, activeCloudEvents.isEmpty {
            currentBatchFailure = nil
            batchHasDataTransfer = false
        }
        batchHasDataTransfer = batchHasDataTransfer || isDataTransfer

        if event.succeeded {
            if isDataTransfer {
                recordSuccessfulTransfer(at: event.endDate ?? .now)
            }
            if event.type == .import {
                scheduleCloudDataRefresh()
            }
        } else {
            currentBatchFailure = event.error?.localizedDescription ?? "未知错误"
        }

        guard activeCloudEvents.isEmpty else {
            syncState = .syncing
            return
        }

        if let currentBatchFailure {
            syncState = .failed(currentBatchFailure)
        } else {
            syncState = batchHasDataTransfer || lastCloudSyncDate != nil
                ? .succeeded
                : .idle
        }
    }

    private func recordSuccessfulTransfer(at date: Date) {
        guard lastCloudSyncDate.map({ date > $0 }) ?? true else { return }
        lastCloudSyncDate = date
        UserDefaults.standard.set(date, forKey: lastSuccessfulTransferKey)
    }

    private func scheduleCloudDataRefresh() {
        cloudRefreshTask?.cancel()
        cloudRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            AppNotifications.postCloudDataChanged()
            self?.cloudRefreshTask = nil
        }
    }
}
