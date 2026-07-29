//
//  SpeechTranscriptionService.swift
//  BB-Memo
//

import AVFoundation
import Foundation
import Observation
import Speech

@Observable
@MainActor
final class SpeechTranscriptionService {
    enum State: Equatable {
        case idle
        case authorizing
        case recording
        case finishing

        var buttonTitle: String {
            switch self {
            case .idle: "语音"
            case .authorizing: "准备"
            case .recording: "停止"
            case .finishing: "识别"
            }
        }

        var isActive: Bool { self != .idle }
        var showsProgress: Bool { self == .authorizing || self == .finishing }
    }

    enum ServiceError: LocalizedError {
        case speechPermissionDenied
        case microphonePermissionDenied
        case recognizerUnavailable
        case audioUnavailable

        var errorDescription: String? {
            switch self {
            case .speechPermissionDenied:
                return "请在系统设置中允许 BB Memo 使用语音识别。"
            case .microphonePermissionDenied:
                return "请在系统设置中允许 BB Memo 使用麦克风。"
            case .recognizerUnavailable:
                return "语音识别服务暂时不可用，请稍后重试。"
            case .audioUnavailable:
                return "无法启动录音，请检查是否有其他应用正在使用麦克风。"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    var isActive: Bool { state.isActive }
    var isRecording: Bool { state == .recording }

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledAudioTap = false
    private var activeSessionID: UUID?
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishTimeoutTask: Task<Void, Never>?

    func start() async {
        guard state == .idle else { return }
        let sessionID = UUID()
        activeSessionID = sessionID
        state = .authorizing
        transcript = ""
        errorMessage = nil

        do {
            try await authorize()
            try Task.checkCancellation()
            guard activeSessionID == sessionID else { throw CancellationError() }

            let recognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent)
                ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
            guard let recognizer, recognizer.isAvailable else {
                throw ServiceError.recognizerUnavailable
            }

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    self?.handleRecognitionResult(result, error: error, sessionID: sessionID)
                }
            }

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw ServiceError.audioUnavailable
            }

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            hasInstalledAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
            guard activeSessionID == sessionID else { throw CancellationError() }
            state = .recording
        } catch {
            if activeSessionID == sessionID {
                cleanup(cancelRecognition: true)
            }
            if !(error is CancellationError) {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? ServiceError.audioUnavailable.localizedDescription
            }
        }
    }

    /// 正常结束录音，并等待识别器返回最终文本。
    func finish() async {
        switch state {
        case .idle:
            return
        case .authorizing:
            cancel()
            return
        case .recording:
            state = .finishing
            stopCapturingAudio()
            recognitionRequest?.endAudio()
            recognitionTask?.finish()
            scheduleFinishTimeout()
        case .finishing:
            break
        }

        guard state != .idle else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }

    /// 用户离开页面或撤销操作时立即取消，不等待最终结果。
    func cancel() {
        cleanup(cancelRecognition: true)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID else { return }

        if let result {
            transcript = result.bestTranscription.formattedString
            if result.isFinal {
                cleanup(cancelRecognition: false)
                return
            }
        }

        if let error {
            let shouldReport = state == .recording
            print("Speech recognition failed: \(error)")
            cleanup(cancelRecognition: true)
            if shouldReport {
                errorMessage = "语音识别中断，请重试。"
            }
        }
    }

    private func stopCapturingAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
    }

    private func scheduleFinishTimeout() {
        let sessionID = activeSessionID
        finishTimeoutTask?.cancel()
        finishTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled,
                  let self,
                  self.activeSessionID == sessionID,
                  self.state == .finishing else { return }
            self.cleanup(cancelRecognition: true)
        }
    }

    private func cleanup(cancelRecognition: Bool) {
        stopCapturingAudio()
        recognitionRequest?.endAudio()
        if cancelRecognition {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        recognitionRequest = nil
        activeSessionID = nil
        state = .idle
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func authorize() async throws {
        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw ServiceError.speechPermissionDenied
        }
        guard await requestMicrophonePermission() else {
            throw ServiceError.microphonePermissionDenied
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization {
                continuation.resume(returning: $0)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }
}
