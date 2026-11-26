import Foundation
import FluidAudio
import os

private let logger = Logger.speaky(category: "ParakeetEngine")

/// Thread-safe transcription engine using an actor to serialize concurrent calls.
/// `AsrManager` and `VadManager` are non-Sendable third-party types, so they are
/// wrapped in `@unchecked Sendable` boxes to allow the actor to own them while
/// still providing compiler-enforced serialization of all access.
actor ParakeetEngine: TranscriptionEngine {
    private final class AsrBox: @unchecked Sendable {
        var manager: AsrManager?
    }

    private final class VadBox: @unchecked Sendable {
        var manager: VadManager?
    }

    private final class ModelsBox: @unchecked Sendable {
        var models: AsrModels?
    }

    private let asrBox = AsrBox()
    private let vadBox = VadBox()
    private let modelsBox = ModelsBox()
    private let version: AsrModelVersion

    /// Words to boost with FluidAudio's CTC vocabulary rescoring.
    private var vocabulary: [String] = []
    /// Vocabulary currently configured on the manager, so it isn't rebuilt needlessly.
    private var configuredVocabulary: [String] = []
    private var ctcDownload: Task<Void, Never>?

    init(version: AsrModelVersion = .v3) {
        self.version = version
    }

    func transcribe(audioFileURL: URL, language: String) async throws -> TranscriptionResult {
        try await ensureModelsLoaded()

        guard let asrManager = asrBox.manager else {
            throw TranscriptionError.modelNotLoaded
        }

        let audioSamples = try AudioFileLoader.loadSamples(from: audioFileURL)
        let durationSeconds = Double(audioSamples.count) / 16000.0

        var speechAudio = audioSamples

        // Use VAD for longer audio to filter non-speech segments
        if durationSeconds >= 20.0 {
            if vadBox.manager == nil {
                let vadConfig = VadConfig(defaultThreshold: 0.7)
                vadBox.manager = try? await VadManager(config: vadConfig)
            }
            if let vadManager = vadBox.manager {
                do {
                    let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                    if !segments.isEmpty {
                        speechAudio = segments.flatMap { $0 }
                    }
                } catch {
                    logger.notice("VAD segmentation failed; using full audio: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // Pad with 1 second of silence to help capture final punctuation
        let trailingSilenceSamples = 16_000
        let maxSingleChunkSamples = 240_000
        if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
            speechAudio += [Float](repeating: 0, count: trailingSilenceSamples)
        }

        logger.info("Transcribing \(speechAudio.count) samples (\(String(format: "%.1f", Double(speechAudio.count) / 16000.0))s)")
        let result = try await asrManager.transcribe(speechAudio)
        var text = result.text
        if let applied = result.ctcAppliedTerms, !applied.isEmpty, let tokens = result.tokenTimings, !tokens.isEmpty {
            // Boosting rewrote the text; keep only its safe one-word fixes.
            let heard = tokens.map(\.token).joined()
                .replacingOccurrences(of: "\u{2581}", with: " ")
                .trimmingCharacters(in: .whitespaces)
            text = BoostGuard.filter(original: heard, boosted: result.text)
        }
        logger.info("Transcription result: \(text.count) chars — \"\(text.prefix(100), privacy: .public)\"")

        return TranscriptionResult(
            text: text,
            language: language == "auto" ? nil : language,
            duration: durationSeconds,
            segments: []
        )
    }

    // MARK: - Private

    private func ensureModelsLoaded() async throws {
        if asrBox.manager != nil { return }

        let models: AsrModels
        if let cached = modelsBox.models {
            models = cached
        } else {
            do {
                models = try await AsrModels.loadFromCache(configuration: nil, version: version)
                modelsBox.models = models
                logger.info("Parakeet models loaded for first time (version: \(String(describing: self.version), privacy: .public))")
            } catch {
                logger.error("Failed to load Parakeet models: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrBox.manager = manager
        configuredVocabulary = []
        await configureVocabularyBoosting()
    }

    // MARK: - Vocabulary boosting

    func setVocabulary(_ words: [String]) async {
        guard words != vocabulary else { return }
        vocabulary = words
        await configureVocabularyBoosting()
    }

    /// Point the manager's CTC rescoring at the current vocabulary. The small CTC
    /// model it needs is downloaded in the background the first time; dictation
    /// never waits for it, it just isn't boosted until the download finishes.
    private func configureVocabularyBoosting() async {
        guard let manager = asrBox.manager, vocabulary != configuredVocabulary else { return }
        let words = vocabulary
        guard !words.isEmpty else {
            manager.disableVocabularyBoosting()
            configuredVocabulary = []
            logger.info("Vocabulary boosting off")
            return
        }

        let directory = CtcModels.defaultCacheDirectory(for: .ctc110m)
        guard CtcModels.modelsExist(at: directory) else {
            startCtcDownload()
            return
        }

        do {
            let ctcModels = try await CtcModels.load(from: directory, variant: .ctc110m)
            let tokenizer = try await CtcTokenizer.load(from: directory)
            let terms = words.compactMap { word -> CustomVocabularyTerm? in
                let ids = tokenizer.encode(word)
                return ids.isEmpty ? nil : CustomVocabularyTerm(text: word, ctcTokenIds: ids)
            }
            try await manager.configureVocabularyBoosting(
                vocabulary: CustomVocabularyContext(terms: terms),
                ctcModels: ctcModels
            )
            configuredVocabulary = words
            logger.info("Vocabulary boosting on for \(terms.count) words")
        } catch {
            logger.error("Vocabulary boosting unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startCtcDownload() {
        guard ctcDownload == nil else { return }
        logger.info("Downloading the vocabulary boosting model")
        ctcDownload = Task { [weak self] in
            do {
                try await CtcModels.download(variant: .ctc110m)
            } catch {
                logger.error("Vocabulary model download failed: \(error.localizedDescription, privacy: .public)")
            }
            await self?.ctcDownloadFinished()
        }
    }

    private func ctcDownloadFinished() async {
        ctcDownload = nil
        if CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory(for: .ctc110m)) {
            await configureVocabularyBoosting()
        }
    }

    func warmUp() async throws {
        try await ensureModelsLoaded()

        // Run a short silence inference to prime the CoreML/ANE pipeline.
        // Loading models alone isn't enough — the first prediction triggers
        // device-specific compilation and memory allocation that adds latency.
        if let manager = asrBox.manager {
            let silence = [Float](repeating: 0, count: 16000)
            _ = try? await manager.transcribe(silence)
        }

        logger.info("Parakeet engine warmed up — inference pipeline primed")
    }

    func cleanup() {
        logger.info("Parakeet engine cleanup")
        asrBox.manager?.cleanup()
        asrBox.manager = nil
        configuredVocabulary = []
        vadBox.manager = nil
    }
}
