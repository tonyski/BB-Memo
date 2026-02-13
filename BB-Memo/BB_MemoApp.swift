//
//  BB_MemoApp.swift
//  BB-Memo
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import Foundation

@main
struct BB_MemoApp: App {
    @StateObject private var syncDiagnostics: SyncDiagnostics
    private let sharedModelContainer: ModelContainer

    init() {
        let bootstrap = AppContainerFactory.make()
        self.sharedModelContainer = bootstrap.container
        _syncDiagnostics = StateObject(
            wrappedValue: SyncDiagnostics(
                iCloudContainerIdentifier: AppContainerFactory.iCloudContainerIdentifier,
                storageMode: bootstrap.storageMode,
                startupMessage: bootstrap.startupMessage
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    DispatchQueue.global(qos: .utility).async {
                        AppDataMaintenance.runOnLaunch(container: sharedModelContainer)
                    }
                }
                .task {
                    await syncDiagnostics.refreshAccountStatus()
                }
                .environmentObject(syncDiagnostics)
                #if os(macOS)
                .frame(minWidth: 700, minHeight: 500)
                #endif
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 960, height: 680)
        #endif
    }
}

/// 启动维护任务：修复派生字段、标签去重、计数校准
private enum AppDataMaintenance {
    static func runOnLaunch(container: ModelContainer) {
        let context = ModelContext(container)
        do {
            try MemoMaintenance.backfillDerivedFields(in: context)
            let mergedCount = try TagDeduplicator.mergeDuplicates(in: context)
            try TagUsageCounter.resyncAll(in: context)
            if mergedCount > 0 {
                print("AppDataMaintenance: merged \(mergedCount) duplicate tags.")
            }
        } catch {
            print("AppDataMaintenance failed: \(error)")
        }
    }
}
