import Foundation
import SwiftWhisper
import os

private let logger = Logger.speaky(category: "WhisperEngine")

/// Thread-safe transcription engine using an actor to serialize concurrent calls.
/// `Whisper` is a non-Sendable third-party type, wrapped in an `@unchecked Sendable`
/// box to allow the actor to own it while still providing compiler-enforced serialization.
actor WhisperEngine: TranscriptionEngine {
    private final class WhisperBox: @unchecked Sendable {
        var whisper: Whisper?
    }

    private let box = WhisperBox()

    func loadModel(path: String) throws {
        box.whisper = nil
        let url = URL(fileURLWithPath: path)
        box.whisper = Whisper(fromFileURL: url)
    }

    func cleanup() {
        box.whisper = nil
    }

    func warmUp() async throws {
        guard let whisper = box.whisper else { return }
        // Run a short silence inference to prime internal caches (KV cache,
        // Metal shaders, memory pools). Without this, the first real
        // transcription pays a significant one-time latency penalty.
        let silence = [Float](repeating: 0, count: 16000)
        whisper.params.language = .english
        _ = try? await whisper.transcribe(audioFrames: silence)
        logger.info("Whisper engine warmed up — inference pipeline primed")
    }

    func transcribe(audioFileURL: URL, language: String) async throws -> TranscriptionResult {
        guard let whisper = box.whisper else { throw TranscriptionError.modelNotLoaded }

        let audioFrames = try AudioFileLoader.loadSamples(from: audioFileURL)

        // whisper.cpp needs at least ~1 second of audio (16000 samples at 16kHz)
        // and crashes with assertion if audio is too short for encoding
        let minSamples = 16000 // 1 second at 16kHz
        let paddedFrames: [Float]
        if audioFrames.count < minSamples {
            // Pad with silence to minimum length
            paddedFrames = audioFrames + [Float](repeating: 0, count: minSamples - audioFrames.count)
        } else {
            paddedFrames = audioFrames
        }

        let startTime = Date()

        // Set language - avoid auto-detect which can crash on short audio
        if language != "auto" {
            if let lang = WhisperLanguage(rawValue: language) {
                whisper.params.language = lang
            }
        } else {
            // Default to English for auto-detect to avoid crash in whisper_lang_auto_detect
            whisper.params.language = .english
        }

        let segments = try await whisper.transcribe(audioFrames: paddedFrames)

        let text = segments.map(\.text).joined()
        let duration = Date().timeIntervalSince(startTime)

        let resultSegments = segments.map { seg in
            TranscriptionResult.Segment(
                text: seg.text,
                start: TimeInterval(seg.startTime) / 1000.0,
                end: TimeInterval(seg.endTime) / 1000.0
            )
        }

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language == "auto" ? nil : language,
            duration: duration,
            segments: resultSegments
        )
    }

}
