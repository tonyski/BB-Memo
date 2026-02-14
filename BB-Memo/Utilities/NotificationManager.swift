//
//  NotificationManager.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import Foundation
import UserNotifications

/// 本地通知管理器：提醒调度 & 取消
enum NotificationManager {
    enum ReminderScheduleResult {
        case scheduled
        case permissionDenied
        case failed(String)
    }

    /// 为 Memo 调度定时提醒
    /// - Parameters:
    ///   - memoID: Memo 的唯一标识字符串
    ///   - content: Memo 内容（截取前 50 字符作为通知正文）
    ///   - date: 提醒时间
    static func scheduleReminder(memoID: String, content: String, at date: Date) async -> ReminderScheduleResult {
        let center = UNUserNotificationCenter.current()
        let request = makeRequest(memoID: memoID, content: content, at: date)

        let settings = await notificationSettings(center: center)
        let status = settings.authorizationStatus
        if status == .denied {
            return .permissionDenied
        }

        if status == .notDetermined {
            do {
                let granted = try await requestAuthorization(center: center, options: [.alert, .sound, .badge])
                guard granted else { return .permissionDenied }
            } catch {
                print("通知权限请求失败: \(error)")
                return .failed(error.localizedDescription)
            }
        }

        do {
            try await add(request, to: center)
            return .scheduled
        } catch {
            print("调度提醒失败: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    /// 取消 Memo 对应的提醒
    static func cancelReminder(memoID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["memo_\(memoID)"])
    }

    private static func makeRequest(memoID: String, content: String, at date: Date) -> UNNotificationRequest {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "BB Memo 提醒"
        notificationContent.body = String(content.prefix(50))
        notificationContent.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "memo_\(memoID)",
            content: notificationContent,
            trigger: trigger
        )
    }

    private static func notificationSettings(center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func requestAuthorization(
        center: UNUserNotificationCenter,
        options: UNAuthorizationOptions
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private static func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
