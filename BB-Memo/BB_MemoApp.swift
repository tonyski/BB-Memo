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
                        TagDeduplicator.mergeDuplicatesIfNeeded(container: sharedModelContainer)
                        TagUsageCounter.backfillIfNeeded(container: sharedModelContainer)
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
