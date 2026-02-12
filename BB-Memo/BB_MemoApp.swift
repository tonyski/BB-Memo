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
    var sharedModelContainer: ModelContainer = {
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
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch let cloudError {
            do {
                return try ModelContainer(for: schema, configurations: [localConfiguration])
            } catch let localError {
                // 模型变更导致旧数据不兼容时，清除旧数据重试（本地配置）
                let url = localConfiguration.url
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
                do {
                    return try ModelContainer(for: schema, configurations: [localConfiguration])
                } catch let retryError {
                    do {
                        return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
                    } catch {
                        fatalError(
                            "Could not create ModelContainer. cloudError=\(cloudError), localError=\(localError), retryError=\(retryError), inMemoryError=\(error)"
                        )
                    }
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    DispatchQueue.global(qos: .utility).async {
                        TagDeduplicator.mergeDuplicatesIfNeeded(container: sharedModelContainer)
                        TagUsageCounter.backfillIfNeeded(container: sharedModelContainer)
                    }
                }
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
