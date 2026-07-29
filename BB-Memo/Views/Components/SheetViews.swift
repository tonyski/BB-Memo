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
    }
}

struct SettingsSheetView: View {
    var body: some View {
        SettingsView()
    }
}

extension View {
    func memoEditorSheetPresentation() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
