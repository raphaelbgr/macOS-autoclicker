//
//  OCRMatcher.swift
//  macOS AutoClicker
//
//  OCR-based text matching via Vision. Ported from src/ocr.py.
//  Recognizes text on the captured screen, then checks whether any of the
//  user's comma-separated patterns appear (case-insensitive OR logic).
//

import AppKit
import CoreGraphics
import Foundation
import Vision

enum OCRMatcher {

    /// Recognize all text on the image. Mirrors Python `recognize_text`.
    /// Returns the recognized strings, one per detected line/word.
    static func recognizeText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision1

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        // VNRecognizeTextRequest.results is [VNRecognizedTextObservation].
        // Each observation's topCandidates(_) returns [RecognizedText],
        // and .string is the recognized line. The API requires an explicit
        // max count (no default).
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// True if any of `patterns` appears in the recognized text.
    /// Case-insensitive substring match. Mirrors Python `text_matches_any`.
    /// Returns (matched, whichPattern, allRecognized).
    static func textMatchesAny(
        in image: CGImage,
        patterns: [String]
    ) -> (matched: Bool, matchedPattern: String?, recognized: [String]) {
        let recognized = recognizeText(in: image)
        guard !patterns.isEmpty else { return (false, nil, recognized) }
        let loweredTexts = recognized.map { $0.lowercased() }
        for pattern in patterns {
            let p = pattern.trimmingCharacters(in: .whitespaces).lowercased()
            guard !p.isEmpty else { continue }
            if loweredTexts.contains(where: { $0.contains(p) }) {
                return (true, pattern, recognized)
            }
        }
        return (false, nil, recognized)
    }
}
