//
//  AppNotifications.swift
//  BB
//
//  Created by Codex on 2026/2/12.
//

import Foundation

extension Notification.Name {
    static let memoDataChanged = Notification.Name("memoDataChanged")
}

enum AppNotifications {
    static func postMemoDataChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .memoDataChanged, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .memoDataChanged, object: nil)
            }
        }
    }
}
