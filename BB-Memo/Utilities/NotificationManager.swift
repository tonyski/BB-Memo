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
    /// 为 Memo 调度定时提醒
    /// - Parameters:
    ///   - memoID: Memo 的唯一标识字符串
    ///   - content: Memo 内容（截取前 50 字符作为通知正文）
    ///   - date: 提醒时间
    static func scheduleReminder(memoID: String, content: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        let request = makeRequest(memoID: memoID, content: content, at: date)

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request) { error in
                    if let error {
                        print("调度提醒失败: \(error)")
                    }
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        print("通知权限请求失败: \(error)")
                        return
                    }
                    guard granted else { return }
                    center.add(request) { addError in
                        if let addError {
                            print("调度提醒失败: \(addError)")
                        }
                    }
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    /// 取消 Memo 对应的提醒
    static func cancelReminder(memoID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["memo_\(memoID)"])
    }

    private static func makeRequest(memoID: String, content: String, at date: Date) -> UNNotificationRequest {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "BB 提醒"
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
}
