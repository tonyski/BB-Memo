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
    struct ReminderSnapshot: Sendable {
        let memoID: String
        let content: String
        let date: Date
    }

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
        guard date > .now else {
            return .failed("提醒时间必须晚于当前时间")
        }
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

    /// 用 CloudKit 中的提醒状态校准本机待处理通知，不主动请求权限。
    static func reconcileReminders(_ reminders: [ReminderSnapshot]) async {
        let center = UNUserNotificationCenter.current()
        let futureReminders = reminders.filter { $0.date > .now }
        let pending = await pendingRequests(center: center)
        let pendingReminders = pending.filter { $0.identifier.hasPrefix("memo_") }
        let pendingByIdentifier = Dictionary(
            uniqueKeysWithValues: pendingReminders.map { ($0.identifier, $0) }
        )
        let desiredIdentifiers = Set(futureReminders.map(reminderIdentifier))
        let staleIdentifiers = pendingByIdentifier.keys.filter {
            !desiredIdentifiers.contains($0)
        }

        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: Array(staleIdentifiers)
            )
        }

        let settings = await notificationSettings(center: center)
        guard canScheduleWithoutPrompt(settings.authorizationStatus) else { return }

        for reminder in futureReminders {
            let identifier = reminderIdentifier(reminder)
            if let pendingRequest = pendingByIdentifier[identifier],
               requestMatches(pendingRequest, reminder: reminder) {
                continue
            }
            let request = makeRequest(
                memoID: reminder.memoID,
                content: reminder.content,
                at: reminder.date
            )
            try? await add(request, to: center)
        }
    }

    private static func makeRequest(memoID: String, content: String, at date: Date) -> UNNotificationRequest {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "BB Memo 提醒"
        notificationContent.body = String(content.prefix(50))
        notificationContent.sound = .default
        notificationContent.userInfo = [
            "memoID": memoID,
            "reminderDate": date.timeIntervalSince1970
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSinceNow, 1),
            repeats: false
        )
        return UNNotificationRequest(
            identifier: "memo_\(memoID)",
            content: notificationContent,
            trigger: trigger
        )
    }

    private static func reminderIdentifier(_ reminder: ReminderSnapshot) -> String {
        "memo_\(reminder.memoID)"
    }

    private static func requestMatches(
        _ request: UNNotificationRequest,
        reminder: ReminderSnapshot
    ) -> Bool {
        guard request.content.title == "BB Memo 提醒",
              request.content.body == String(reminder.content.prefix(50)),
              request.content.userInfo["memoID"] as? String == reminder.memoID,
              let timestamp = request.content.userInfo["reminderDate"] as? TimeInterval else {
            return false
        }
        return abs(timestamp - reminder.date.timeIntervalSince1970) < 1
    }

    private static func notificationSettings(center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func pendingRequests(center: UNUserNotificationCenter) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests {
                continuation.resume(returning: $0)
            }
        }
    }

    private static func canScheduleWithoutPrompt(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
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
