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
        NotificationCenter.default.post(name: .memoDataChanged, object: nil)
    }
}
