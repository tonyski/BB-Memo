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

    /// 请求通知权限
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("通知权限请求失败: \(error)")
            return false
        }
    }

    /// 为 Memo 调度定时提醒
    /// - Parameters:
    ///   - memoID: Memo 的唯一标识字符串
    ///   - content: Memo 内容（截取前 50 字符作为通知正文）
    ///   - date: 提醒时间
    static func scheduleReminder(memoID: String, content: String, at date: Date) {
        let center = UNUserNotificationCenter.current()

        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "BB 提醒"
        notificationContent.body = String(content.prefix(50))
        notificationContent.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "memo_\(memoID)",
            content: notificationContent,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("调度提醒失败: \(error)")
            }
        }
    }

    /// 取消 Memo 对应的提醒
    static func cancelReminder(memoID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["memo_\(memoID)"])
    }
}
