//
//  ContentView.swift
//  BB-Memo
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var syncDiagnostics: SyncDiagnostics
    @State private var showComposer = false
    @State private var showSidebar = false

    var body: some View {
        if syncDiagnostics.storageMode == .inMemoryFallback {
            ContentUnavailableView {
                Label(
                    "数据存储不可用",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
            } description: {
                Text(
                    "为避免产生无法同步的数据，当前已暂停编辑。请检查 iCloud、存储空间或系统权限，然后重新启动应用。"
                )
            }
        } else {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    MemoTimelineView(showSidebar: $showSidebar)

                    if !showSidebar {
                        Button {
                            showComposer = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppTheme.onBrandAccent)
                                .frame(width: 54, height: 54)
                                .background(AppTheme.brandAccent)
                                .clipShape(Circle())
                                .shadow(
                                    color: AppTheme.brandAccent.opacity(0.3),
                                    radius: 10,
                                    y: 5
                                )
                        }
                        .accessibilityLabel("新建笔记")
                        .accessibilityHint("打开编辑器，新建一条笔记")
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottom
                )
                .animation(.default, value: showSidebar)
                .sheet(isPresented: $showComposer) {
                    MemoEditorSheetView(memo: nil)
                }
            }
        }
    }
}
