//
//  Theme.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI

/// BB 品牌设计系统 - 极简/高级/紫色调
enum AppTheme {
    // MARK: - 核心色彩
    
    static var brandAccent: Color {
        #if os(iOS)
        return Color(uiColor: .init { $0.userInterfaceStyle == .dark ? .init(white: 0.85, alpha: 1) : .init(white: 0.15, alpha: 1) })
        #else
        return Color.accentColor
        #endif
    }
    
    static let action = Color(red: 0.35, green: 0.4, blue: 0.5) // Slate/Cool Gray for actions
    static let success = Color(red: 0.4, green: 0.55, blue: 0.45) // Sage
    static let warning = Color(red: 0.7, green: 0.55, blue: 0.4)  // Ochre/Sand
    
    // MARK: - 标签色彩
    
    static func tagColor(for name: String) -> Color { .secondary }

    // MARK: - 视觉样式
    
    static var cardBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var background: Color {
        #if os(iOS)
        Color(UIColor.systemGroupedBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    static var brandGradient: LinearGradient {
        .linearGradient(colors: [brandAccent, brandAccent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    enum Layout {
        static let screenPadding: CGFloat = 8
        static let cardPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 12
        static let cardSpacing: CGFloat = 8
        static let fontDesign: Font.Design = .rounded
    }

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let snappy = Animation.easeOut(duration: 0.2)
}

// MARK: - 视觉辅助

extension View {
    func memoCardStyle(cornerRadius: CGFloat = AppTheme.Layout.cornerRadius) -> some View {
        self.padding(AppTheme.Layout.cardPadding)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
    
    func premiumShadow() -> some View {
        self.shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - 按钮样式

struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { .init() }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { .init() }
}

// MARK: - 环境扩展

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        #if os(iOS)
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        return keyWindow?.safeAreaInsets.asEdgeInsets ?? EdgeInsets()
        #else
        return EdgeInsets()
        #endif
    }
}

#if os(iOS)
extension UIEdgeInsets {
    var asEdgeInsets: EdgeInsets { .init(top: top, leading: left, bottom: bottom, trailing: right) }
}
#endif
