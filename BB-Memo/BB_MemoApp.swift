//
//  BB_MemoApp.swift
//  BB-Memo
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

@main
struct BB_MemoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var syncDiagnostics: SyncDiagnostics
    private let sharedModelContainer: ModelContainer
    private let maintenanceActor: AppDataMaintenanceActor

    init() {
        let bootstrap = AppContainerFactory.make()
        self.sharedModelContainer = bootstrap.container
        self.maintenanceActor = AppDataMaintenanceActor(modelContainer: bootstrap.container)
        _syncDiagnostics = StateObject(
            wrappedValue: SyncDiagnostics(
                iCloudContainerIdentifier: AppContainerFactory.iCloudContainerIdentifier,
                storageMode: bootstrap.storageMode
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    if let reminders = await maintenanceActor.runLaunchMaintenance() {
                        await NotificationManager.reconcileReminders(reminders)
                    }
                }
                .task {
                    await syncDiagnostics.refreshAccountStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudDataChanged)) { _ in
                    Task {
                        if let reminders = await maintenanceActor.reconcileCloudDerivedData() {
                            await NotificationManager.reconcileReminders(reminders)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await syncDiagnostics.refreshAccountStatus()
                        if let reminders = await maintenanceActor.refreshReminders() {
                            await NotificationManager.reconcileReminders(reminders)
                        }
                    }
                }
                .environment(\.locale, .autoupdatingCurrent)
                .environmentObject(syncDiagnostics)
        }
        .modelContainer(sharedModelContainer)
    }
}

/// 在独立 SwiftData actor 中执行维护，避免导入后阻塞主线程。
@ModelActor
private actor AppDataMaintenanceActor {
    private var hasRunOnLaunch = false

    func runLaunchMaintenance() -> [NotificationManager.ReminderSnapshot]? {
        guard !hasRunOnLaunch else { return nil }
        hasRunOnLaunch = true
        return reconcileDerivedData(source: "launch")
    }

    func reconcileCloudDerivedData() -> [NotificationManager.ReminderSnapshot]? {
        reconcileDerivedData(source: "CloudKit import")
    }

    func refreshReminders() -> [NotificationManager.ReminderSnapshot]? {
        do {
            let memos = try modelContext.fetch(reminderDescriptor)
            let result = reminderSnapshots(from: memos)
            if result.hasChanges {
                try modelContext.save()
            }
            return result.snapshots
        } catch {
            modelContext.rollback()
            print("Reminder reconciliation failed: \(error)")
            return nil
        }
    }

    private func reconcileDerivedData(source: String) -> [NotificationManager.ReminderSnapshot]? {
        do {
            let memos = try modelContext.fetch(FetchDescriptor<Memo>())
            let tags = try modelContext.fetch(FetchDescriptor<Tag>())
            let memoChanged = MemoMaintenance.reconcile(memos)
            let tagChanged = TagMaintenance.reconcile(
                tags: tags,
                memos: memos,
                in: modelContext
            )
            let reminderResult = reminderSnapshots(from: memos)
            if memoChanged || tagChanged || reminderResult.hasChanges {
                try modelContext.save()
            }
            return reminderResult.snapshots
        } catch {
            modelContext.rollback()
            print("Derived-data reconciliation failed (\(source)): \(error)")
            return nil
        }
    }

    private var reminderDescriptor: FetchDescriptor<Memo> {
        FetchDescriptor(
            predicate: #Predicate<Memo> {
                $0.deletedAt == nil && $0.reminderDate != nil
            }
        )
    }

    private func reminderSnapshots(from memos: [Memo]) -> (
        snapshots: [NotificationManager.ReminderSnapshot],
        hasChanges: Bool
    ) {
        var reminders: [NotificationManager.ReminderSnapshot] = []
        var clearedExpiredReminder = false

        for memo in memos where !memo.isInRecycleBin {
            guard let date = memo.reminderDate else { continue }
            if date <= .now {
                memo.reminderDate = nil
                clearedExpiredReminder = true
            } else {
                reminders.append(
                    .init(memoID: memo.reminderIdentifier, content: memo.content, date: date)
                )
            }
        }
        return (reminders, clearedExpiredReminder)
    }
}
