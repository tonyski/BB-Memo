//
//  ReminderPickerView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI

/// 提醒时间选择器 — 简洁的 compact 样式
struct ReminderPickerView: View {
    @Binding var selectedDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate: Date = .now.addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 简洁日期时间选择
                DatePicker(
                    "提醒时间",
                    selection: $pickerDate,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                .labelsHidden()

                Spacer()

                // 确定按钮
                Button {
                    selectedDate = pickerDate
                    dismiss()
                } label: {
                    Text("保存提醒")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.brandAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .navigationTitle("设置提醒")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if selectedDate != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("清除") {
                            selectedDate = nil
                            dismiss()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .onAppear {
                if let existing = selectedDate {
                    pickerDate = existing
                }
            }
        }
        .presentationDetents([.medium])
    }
}
