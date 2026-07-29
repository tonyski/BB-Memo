//
//  HapticFeedback.swift
//  BB-Memo
//

import Foundation
import UIKit

enum HapticFeedback {
    case light, medium, selection

    func play() {
        switch self {
        case .light:    UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:   UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
