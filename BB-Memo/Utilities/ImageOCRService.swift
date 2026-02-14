//
//  ImageOCRService.swift
//  BB
//
//  Created by Codex on 2026/2/14.
//

import Foundation
import Vision

enum ImageOCRService {
    enum Error: LocalizedError {
        case invalidImageData
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImageData:
                return "无法读取图片数据，请重新选择一张图片。"
            case .noTextFound:
                return "没有识别到可用文字，请换一张更清晰的图片。"
            }
        }
    }

    static func recognizeText(from imageData: Data, minimumConfidence: Float = 0.35) async throws -> String {
        guard !imageData.isEmpty else {
            throw Error.invalidImageData
        }

        let observations = try await Task.detached(priority: .userInitiated) { () -> [VNRecognizedTextObservation] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])
            return request.results ?? []
        }.value

        let orderedLines = observations
            .sorted(by: compareTextLayout)
            .compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                guard candidate.confidence >= minimumConfidence else {
                    return nil
                }
                let normalized = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? nil : normalized
            }

        guard !orderedLines.isEmpty else {
            throw Error.noTextFound
        }
        return orderedLines.joined(separator: "\n")
    }

    private static func compareTextLayout(_ lhs: VNRecognizedTextObservation, _ rhs: VNRecognizedTextObservation) -> Bool {
        let yDelta = abs(lhs.boundingBox.minY - rhs.boundingBox.minY)
        if yDelta > 0.02 {
            // Vision 坐标系原点在左下，Y 越大越靠上。
            return lhs.boundingBox.minY > rhs.boundingBox.minY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
}
