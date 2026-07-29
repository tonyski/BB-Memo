//
//  AppNotifications.swift
//  BB
//
//  Created by Codex on 2026/2/12.
//

import Foundation
import Combine

extension Notification.Name {
    static let memoDataChanged = Notification.Name("memoDataChanged")
    static let cloudDataChanged = Notification.Name("cloudDataChanged")
}

enum AppNotifications {
    static var dataChanges: AnyPublisher<Void, Never> {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: .memoDataChanged),
            NotificationCenter.default.publisher(for: .cloudDataChanged)
        )
        .map { _ in () }
        .receive(on: RunLoop.main)
        .eraseToAnyPublisher()
    }

    static func postMemoDataChanged() {
        post(.memoDataChanged)
    }

    static func postCloudDataChanged() {
        post(.cloudDataChanged)
    }

    private static func post(_ name: Notification.Name) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: name, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: name, object: nil)
            }
        }
    }
}
