//
//  MemoTimeFilter.swift
//  BB-Memo
//

import Foundation

enum MemoTimeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case today = "今天"
    case week = "近一周"
    case month = "近一月"
    case threeMonths = "近三月"

    var id: String { rawValue }

    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date.now

        switch self {
        case .all:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        }
    }
}
