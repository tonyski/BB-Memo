//
//  CameraTextScannerSheet.swift
//  BB
//
//  Created by Codex on 2026/2/14.
//

#if os(iOS)
import SwiftUI
import VisionKit

@available(iOS 16.0, *)
struct CameraTextScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onRecognizedText: (String) -> Void
    @State private var scannerErrorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            CameraTextScannerView(
                onRecognizedText: { text in
                    onRecognizedText(text)
                    dismiss()
                },
                onFailure: { message in
                    scannerErrorMessage = message
                }
            )
            .ignoresSafeArea()

            HStack(spacing: 12) {
                Text("点按高亮文字即可插入到笔记")
                    .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("取消") {
                    dismiss()
                }
                .font(.system(size: 13, weight: .semibold, design: AppTheme.Layout.fontDesign))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.top, 14)
            .padding(.horizontal, 16)
        }
        .background(Color.black.ignoresSafeArea())
        .alert("扫描不可用", isPresented: Binding(get: {
            scannerErrorMessage != nil
        }, set: { newValue in
            if !newValue {
                scannerErrorMessage = nil
            }
        })) {
            Button("确定", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(scannerErrorMessage ?? "无法启动相机扫描。")
        }
    }
}

@available(iOS 16.0, *)
private struct CameraTextScannerView: UIViewControllerRepresentable {
    let onRecognizedText: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .black
            DispatchQueue.main.async {
                onFailure("当前设备不支持相机实时扫描，请改用“从相册提取”。")
            }
            return fallback
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["zh-Hans", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator

        do {
            try scanner.startScanning()
        } catch {
            print("CameraTextScannerView startScanning failed: \(error)")
            DispatchQueue.main.async {
                onFailure("相机扫描暂时不可用，请稍后重试。")
            }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        (uiViewController as? DataScannerViewController)?.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognizedText: onRecognizedText)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognizedText: (String) -> Void

        init(onRecognizedText: @escaping (String) -> Void) {
            self.onRecognizedText = onRecognizedText
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let textItem) = item else { return }
            let normalized = textItem.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            onRecognizedText(normalized)
        }
    }
}
#endif
