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
                    AppDataMaintenance.runOnLaunchIfNeeded(container: sharedModelContainer)
                }
                .task {
                    await syncDiagnostics.refreshAccountStatus()
                }
                .environment(\.locale, .autoupdatingCurrent)
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

/// 启动维护任务：修复派生字段并校准标签计数
private enum AppDataMaintenance {
    private static let runLock = NSLock()
    private static var hasRunOnLaunch = false

    @MainActor
    static func runOnLaunchIfNeeded(container: ModelContainer) {
        let shouldRun: Bool = {
            runLock.lock()
            defer { runLock.unlock() }
            guard !hasRunOnLaunch else { return false }
            hasRunOnLaunch = true
            return true
        }()
        guard shouldRun else { return }

        let context = ModelContext(container)
        do {
            try MemoMaintenance.backfillDerivedFields(in: context)
            try TagUsageCounter.resyncAll(in: context)
        } catch {
            print("AppDataMaintenance failed: \(error)")
        }
    }
}
