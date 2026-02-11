//
//  BB_MemoApp.swift
//  BB-Memo
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData

@main
struct BB_MemoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Memo.self,
            Tag.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // 模型变更导致旧数据不兼容时，清除旧数据重试
            let url = modelConfiguration.url
            try? FileManager.default.removeItem(at: url)
            // 同时清理 WAL/SHM
            try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    _ = await NotificationManager.requestAuthorization()
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
