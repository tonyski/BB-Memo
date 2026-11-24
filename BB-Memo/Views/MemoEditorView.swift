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
    @State private var isSaving = false
    @State private var showReminderIssueAlert = false
    @State private var reminderIssueMessage = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showImageSourceDialog = false
    @State private var isRecognizingImageText = false
    @State private var showOCRErrorAlert = false
    @State private var ocrErrorMessage = ""
    @State private var speechService = SpeechTranscriptionService()
    @State private var speechBaseContent = ""
    @State private var speechTask: Task<Void, Never>?

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
    private var frequentTagSuggestions: [TagSuggestion] {
        Tag.sortedByUsage(allTags)
            .prefix(3)
            .map { TagSuggestion(name: $0.name) }
    }

    private var mergedTagSuggestions: [TagSuggestion] {
        var result: [TagSuggestion] = []
        var seen = Set<String>()

        for name in selectedTagNames.sorted() {
            let normalized = Tag.normalize(name)
            let key = Tag.normalizedKey(for: normalized)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                result.append(TagSuggestion(name: normalized))
            }
        }

        for suggestion in frequentTagSuggestions {
            let key = Tag.normalizedKey(for: suggestion.name)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                result.append(suggestion)
            }
        }

        for suggestion in aiSuggestions {
            let key = Tag.normalizedKey(for: suggestion.name)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                result.append(suggestion)
            }
        }

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
                        .allowsHitTesting(!speechService.isActive)
                        .task(id: content) {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            let text = content
                            let existingTagNames = allTags.map(\.name)
                            let analysis = Task.detached(priority: .utility) {
                                TagExtractor.suggestTags(
                                    from: text,
                                    existingTagNames: existingTagNames
                                )
                            }
                            let suggestions = await withTaskCancellationHandler {
                                await analysis.value
                            } onCancel: {
                                analysis.cancel()
                            }
                            guard !Task.isCancelled else { return }
                            aiSuggestions = suggestions
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancelSpeechInput()
                        dismiss()
                    }
                        .foregroundStyle(.secondary)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("完成")
                        }
                    }
                        .font(.system(size: 15, weight: .semibold, design: AppTheme.Layout.fontDesign))
                        .foregroundStyle(trimmedContent.isEmpty ? .secondary : AppTheme.brandAccent)
                        .disabled(trimmedContent.isEmpty || isSaving)
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
                    .presentationDetents([.height(360)])
                case .cameraScanner:
                    CameraTextScannerSheet(onRecognizedText: { text in
                        appendRecognizedText(text)
                    })
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
            .alert("语音录入不可用", isPresented: Binding(
                get: { speechService.errorMessage != nil },
                set: { if !$0 { speechService.dismissError() } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(speechService.errorMessage ?? "无法开始语音录入，请稍后重试。")
            }
            .onAppear {
                isFocused = true
            }
            .onDisappear {
                cancelSpeechInput()
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
            .onChange(of: speechService.transcript) { _, transcript in
                updateSpeechTranscript(transcript)
            }
            .interactiveDismissDisabled(isSaving || speechService.isActive)
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
            .animation(nil, value: mergedTagSuggestions.map(\.id))

            HStack(spacing: 10) {
                imageOCRButton
                    .frame(maxWidth: .infinity)
                speechInputButton
                    .frame(maxWidth: .infinity)
                reminderButton
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(AppTheme.cardBackground)
    }

    // MARK: - Actions

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await finishSpeechInput()
        guard !trimmedContent.isEmpty else { return }
        
        HapticFeedback.medium.play()
        let previousReminderDate = memo?.reminderDate
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
                restoreReminderDate(previousReminderDate, for: targetMemo)
                reminderIssueMessage = "内容已保存，但系统通知权限未开启。请到系统设置中允许通知后再设置提醒。"
                showReminderIssueAlert = true
            case .failed:
                restoreReminderDate(previousReminderDate, for: targetMemo)
                reminderIssueMessage = "内容已保存，但提醒创建失败，请稍后再试。"
                showReminderIssueAlert = true
            }
        } else {
            NotificationManager.cancelReminder(memoID: memoID)
        }

        AppNotifications.postMemoDataChanged()
        if !showReminderIssueAlert {
            dismiss()
        }
    }

    private func restoreReminderDate(_ date: Date?, for memo: Memo) {
        reminderDate = date
        do {
            try MemoMutationService.updateReminderDate(date, for: memo, context: modelContext)
        } catch {
            print("MemoEditorView reminder rollback failed: \(error)")
        }
    }

    private func addCustomTag(named raw: String) {
        let canonicalName = canonicalTagName(for: raw)
        guard !canonicalName.isEmpty else { return }
        selectedTagNames.insert(canonicalName)
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
        let key = Tag.normalizedKey(for: normalized)
        return allTags.first { $0.normalizedKey == key }?.name ?? normalized
    }

    private var imageOCRButton: some View {
        Button {
            guard !isRecognizingImageText else { return }
            showImageSourceDialog = true
        } label: {
            compactAccessoryActionStyle {
                imageOCRLabelContent(title: isRecognizingImageText ? "提取中" : "图片")
            }
        }
        .buttonStyle(.plain)
        .disabled(isRecognizingImageText || speechService.isActive)
        .popover(
            isPresented: $showImageSourceDialog,
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
        ) {
            imageSourcePopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func imageOCRLabelContent(title: String) -> some View {
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
        Text(title)
            .font(.system(size: 14, weight: .regular, design: AppTheme.Layout.fontDesign))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var imageSourcePopoverContent: some View {
        VStack(spacing: 8) {
            imageSourceButton("从相册提取", systemImage: "photo.on.rectangle.angled") {
                showImageSourceDialog = false
                showPhotoPicker = true
            }

            imageSourceButton("相机实时扫描", systemImage: "camera.viewfinder") {
                showImageSourceDialog = false
                activeSheet = .cameraScanner
            }
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

    private var reminderButton: some View {
        Button {
            activeSheet = .reminder
            HapticFeedback.light.play()
        } label: {
            compactAccessoryActionStyle {
                reminderLabelContent(title: reminderDate == nil ? "提醒" : reminderCompactButtonTitle)
            }
        }
        .buttonStyle(.plain)
        .disabled(speechService.isActive)
    }

    @ViewBuilder
    private func reminderLabelContent(title: String) -> some View {
        Image(systemName: reminderIconName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(reminderIconColor)
        Text(title)
            .font(.system(size: 14, weight: .regular, design: AppTheme.Layout.fontDesign))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var speechInputButton: some View {
        Button {
            handleSpeechButtonTap()
        } label: {
            compactAccessoryActionStyle(
                accentColor: speechService.isActive ? .red : AppTheme.brandAccent
            ) {
                Group {
                    if speechService.state.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.red)
                    } else {
                        Image(systemName: speechService.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                Text(speechService.state.buttonTitle)
                    .font(.system(size: 14, weight: .regular, design: AppTheme.Layout.fontDesign))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isRecognizingImageText || speechService.state == .finishing)
        .accessibilityLabel(speechService.isActive ? "停止语音录入" : "开始语音录入")
    }

    private func handleSpeechButtonTap() {
        switch speechService.state {
        case .idle:
            beginSpeechInput()
        case .authorizing:
            cancelSpeechInput()
        case .recording:
            speechTask = Task {
                await speechService.finish()
                HapticFeedback.light.play()
            }
        case .finishing:
            break
        }
    }

    private func beginSpeechInput() {
        speechBaseContent = content
        speechTask?.cancel()
        speechTask = Task {
            await speechService.start()
            if speechService.isRecording {
                HapticFeedback.medium.play()
            }
        }
    }

    @MainActor
    private func updateSpeechTranscript(_ transcript: String) {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let base = speechBaseContent
        if base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = normalized
        } else {
            let separator = base.hasSuffix("\n") ? "" : "\n\n"
            content = base + separator + normalized
        }
    }

    @MainActor
    private func finishSpeechInput() async {
        speechTask?.cancel()
        speechTask = nil
        await speechService.finish()
    }

    private func cancelSpeechInput() {
        speechTask?.cancel()
        speechTask = nil
        speechService.cancel()
    }

    private func compactAccessoryActionStyle<Content: View>(
        accentColor: Color = AppTheme.brandAccent,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            content()
        }
        .foregroundStyle(accentColor)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background(accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

}
