//
//  HapticFeedback.swift
//  BB-Memo
//

import Foundation
#if os(iOS)
import UIKit
#endif

/// 跨平台触觉反馈工具 — 消除散落的 #if os(iOS) 样板代码
enum HapticFeedback {
    case light, medium, selection

    func play() {
        #if os(iOS)
        switch self {
        case .light:    UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:   UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}
