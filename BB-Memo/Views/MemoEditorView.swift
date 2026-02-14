//
//  MemoEditorView.swift
//  BB
//
//  Created by Tonyski on 2026/2/11.
//

import SwiftUI
import SwiftData
import PhotosUI

/// 统一的 Memo 编辑器 — 支持新建和编辑已有内容
struct MemoEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTags: [Tag]

    /// 如果为 nil 则表示新建
    var memo: Memo?

    @State private var content = ""
    @State private var reminderDate: Date?
    @State private var aiSuggestions: [TagSuggestion] = []
    @State private var selectedTagNames: Set<String> = []
    @State private var activeSheet: ActiveSheet?
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var showReminderIssueAlert = false
    @State private var reminderIssueMessage = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showImageSourceDialog = false
    @State private var isRecognizingImageText = false
    @State private var showOCRErrorAlert = false
    @State private var ocrErrorMessage = ""

    @FocusState private var isFocused: Bool

    init(memo: Memo?) {
        self.memo = memo
        _content = State(initialValue: memo?.content ?? "")
        _reminderDate = State(initialValue: memo?.reminderDate)
        _selectedTagNames = State(initialValue: Set<String>(memo?.tagsList.map(\.name) ?? []))
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var reminderButtonTitle: String {
        let value = reminderDate?.formatted(
            .dateTime
                .month()
                .day()
                .hour()
                .minute()
                .locale(.autoupdatingCurrent)
        ) ?? "未设置"
        return "设置提醒 · \(value)"
    }
    private var reminderCompactButtonTitle: String {
        reminderDate?.formatted(
            .dateTime
                .month()
                .day()
                .hour()
                .minute()
                .locale(.autoupdatingCurrent)
        ) ?? "设置提醒"
    }
    private var reminderIconName: String {
        reminderDate == nil ? "bell.badge" : "bell.fill"
    }
    private var reminderIconColor: Color {
        reminderDate == nil ? AppTheme.brandAccent : AppTheme.warning
    }
    private enum ActiveSheet: Identifiable {
        case reminder
        case tagPicker
        case cameraScanner

        var id: Int {
            switch self {
            case .reminder: 0
            case .tagPicker: 1
            case .cameraScanner: 2
            }
        }
    }
    private var mergedTagSuggestions: [TagSuggestion] {
        var result = aiSuggestions
        let existingLower = Set(aiSuggestions.map { $0.name.lowercased() })
        let extras = selectedTagNames
            .filter { !existingLower.contains($0.lowercased()) }
            .sorted()
            .map { TagSuggestion(name: $0, isAutoAdded: false) }
        result.append(contentsOf: extras)
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $content)
                        .font(.system(.body, design: AppTheme.Layout.fontDesign, weight: .regular))
                        .lineSpacing(6)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .task(id: content) {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            aiSuggestions = TagExtractor.suggestTags(
                                from: content,
                                existingTagNames: allTags.map(\.name)
                            )
                        }

                    if content.isEmpty {
                        Text("写下你的想法...")
                            .font(.system(.body, design: AppTheme.Layout.fontDesign))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.cardBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomAccessoryArea
            }
            .navigationTitle(memo == nil ? "新建笔记" : "编辑笔记")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Task { await save() }
                    }
                        .font(.system(size: 15, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(trimmedContent.isEmpty ? .secondary : AppTheme.brandAccent)
                        .disabled(trimmedContent.isEmpty)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .reminder:
                    ReminderPickerView(selectedDate: $reminderDate)
                case .tagPicker:
                    TagPickerSheet(
                        allTags: allTags,
                        selectedTagNames: $selectedTagNames,
                        onToggle: { name in
                            toggleTagByName(name)
                        },
                        onCreate: { name in
                            addCustomTag(named: name)
                        }
                    )
                    #if os(iOS)
                    .presentationDetents([.height(360)])
                    #endif
                case .cameraScanner:
                    #if os(iOS)
                    if #available(iOS 16.0, *) {
                        CameraTextScannerSheet(onRecognizedText: { text in
                            appendRecognizedText(text)
                        })
                    } else {
                        Text("当前系统版本不支持相机实时扫描，请改用“从相册提取”。")
                            .padding()
                    }
                    #else
                    Text("当前平台不支持相机实时扫描，请改用“从相册提取”。")
                        .padding()
                    #endif
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .alert("保存失败", isPresented: $showSaveErrorAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .alert("提醒未生效", isPresented: $showReminderIssueAlert) {
                Button("我知道了", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(reminderIssueMessage)
            }
            .alert("图片识别失败", isPresented: $showOCRErrorAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(ocrErrorMessage)
            }
            .onAppear {
                isFocused = true
            }
            .onChange(of: activeSheet) { _, newValue in
                if newValue == nil {
                    isFocused = true
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    await recognizeText(from: item)
                }
            }
        }
    }

    private var bottomAccessoryArea: some View {
        VStack(spacing: 0) {
            AISuggestionBar(
                suggestions: mergedTagSuggestions,
                selectedTagNames: selectedTagNames
            ) { tag in
                toggleTagByName(tag.name)
                HapticFeedback.light.play()
            } onAddCustom: {
                activeSheet = .tagPicker
            }
            .animation(nil, value: selectedTagNames)

            if memo == nil {
                HStack(spacing: 10) {
                    reminderButton(isCompact: true)
                        .frame(maxWidth: .infinity)
                    imageOCRButton
                        .frame(maxWidth: .infinity)
                }
                    .padding(.horizontal, AppTheme.Layout.screenPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
            } else {
                reminderButton(isCompact: false)
                    .padding(.horizontal, AppTheme.Layout.screenPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(AppTheme.cardBackground)
    }

    // MARK: - Actions

    @MainActor
    private func save() async {
        guard !trimmedContent.isEmpty else { return }
        
        HapticFeedback.medium.play()
        let targetMemo: Memo

        do {
            targetMemo = try MemoMutationService.upsertMemo(
                memo: memo,
                content: trimmedContent,
                reminderDate: reminderDate,
                selectedTagNames: selectedTagNames,
                context: modelContext
            )
        } catch {
            saveErrorMessage = "保存失败，请稍后再试。"
            showSaveErrorAlert = true
            return
        }
        let memoID = targetMemo.reminderIdentifier

        // 通知管理
        NotificationManager.cancelReminder(memoID: memoID)
        if let date = reminderDate {
            let scheduleResult = await NotificationManager.scheduleReminder(
                memoID: memoID,
                content: trimmedContent,
                at: date
            )
            switch scheduleResult {
            case .scheduled:
                break
            case .permissionDenied:
                reminderIssueMessage = "内容已保存，但系统通知权限未开启。请到系统设置中允许通知后再设置提醒。"
                showReminderIssueAlert = true
            case .failed:
                reminderIssueMessage = "内容已保存，但提醒创建失败，请稍后再试。"
                showReminderIssueAlert = true
            }
        }

        AppNotifications.postMemoDataChanged()
        if !showReminderIssueAlert {
            dismiss()
        }
    }

    private func addCustomTag(named raw: String) {
        let canonicalName = canonicalTagName(for: raw)
        guard !canonicalName.isEmpty else { return }
        selectedTagNames.insert(canonicalName)
        if aiSuggestions.firstIndex(where: { $0.name.caseInsensitiveCompare(canonicalName) == .orderedSame }) == nil {
            aiSuggestions.insert(TagSuggestion(name: canonicalName, isAutoAdded: false), at: 0)
        }
    }

    private func toggleTagByName(_ raw: String) {
        let canonicalName = canonicalTagName(for: raw)
        guard !canonicalName.isEmpty else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            EditorHelper.toggleTag(canonicalName, selectedTagNames: &selectedTagNames)
        }
    }

    private func canonicalTagName(for raw: String) -> String {
        let normalized = Tag.normalize(raw)
        guard !normalized.isEmpty else { return "" }
        let key = normalized.lowercased()
        return allTags.first {
            let existingKey = $0.normalizedName.isEmpty ? Tag.normalize($0.name).lowercased() : $0.normalizedName
            return existingKey == key
        }?.name ?? normalized
    }

    private var imageOCRButton: some View {
        Button {
            guard !isRecognizingImageText else { return }
            showImageSourceDialog = true
        } label: {
            accessoryActionStyle {
                Group {
                    if isRecognizingImageText {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.brandAccent)
                    } else {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.brandAccent)
                    }
                }
                Text(isRecognizingImageText ? "正在提取文字..." : "提取图片文字")
                    .font(.system(size: 14, weight: .regular, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isRecognizingImageText)
        .popover(
            isPresented: $showImageSourceDialog,
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
        ) {
            imageSourcePopoverContent
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
        }
    }

    @ViewBuilder
    private var imageSourcePopoverContent: some View {
        VStack(spacing: 8) {
            imageSourceButton("从相册提取", systemImage: "photo.on.rectangle.angled") {
                showImageSourceDialog = false
                showPhotoPicker = true
            }

            #if os(iOS)
            imageSourceButton("相机实时扫描", systemImage: "camera.viewfinder") {
                showImageSourceDialog = false
                activeSheet = .cameraScanner
            }
            #endif
        }
        .padding(12)
        .frame(minWidth: 200)
    }

    private func imageSourceButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.brandAccent)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func recognizeText(from item: PhotosPickerItem) async {
        guard !isRecognizingImageText else { return }
        isRecognizingImageText = true
        defer {
            isRecognizingImageText = false
            selectedPhotoItem = nil
        }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                throw ImageOCRService.Error.invalidImageData
            }
            let recognizedText = try await ImageOCRService.recognizeText(from: imageData)
            let normalized = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw ImageOCRService.Error.noTextFound
            }
            appendRecognizedText(normalized)
        } catch is CancellationError {
            return
        } catch {
            if error is ImageOCRService.Error {
                ocrErrorMessage = error.localizedDescription
            } else {
                ocrErrorMessage = "提取文字失败，请稍后再试。"
            }
            showOCRErrorAlert = true
        }
    }

    @MainActor
    private func appendRecognizedText(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if content.isEmpty {
            content = normalized
        } else {
            content += "\n\n\(normalized)"
        }
        HapticFeedback.light.play()
    }

    private func reminderButton(isCompact: Bool) -> some View {
        Button {
            activeSheet = .reminder
            HapticFeedback.light.play()
        } label: {
            accessoryActionStyle {
                Image(systemName: reminderIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reminderIconColor)
                Text(isCompact ? reminderCompactButtonTitle : reminderButtonTitle)
                    .font(.system(size: 14, weight: .regular, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .buttonStyle(.plain)
    }

    private func accessoryActionStyle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
