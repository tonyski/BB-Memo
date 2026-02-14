//
//  SheetViews.swift
//  BB-Memo
//

import SwiftUI

struct MemoEditorSheetView: View {
    let memo: Memo?

    var body: some View {
        MemoEditorView(memo: memo)
            .memoEditorSheetPresentation()
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 400)
            #endif
    }
}

struct SettingsSheetView: View {
    var body: some View {
        SettingsView()
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 520)
            #endif
    }
}

extension View {
    func memoEditorSheetPresentation() -> some View {
        self
            #if os(iOS)
            .presentationDetents([.large])
            #else
            .presentationDetents([.medium, .large])
            #endif
            .presentationDragIndicator(.visible)
    }
}
