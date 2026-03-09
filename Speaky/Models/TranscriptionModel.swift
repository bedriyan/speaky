import Foundation

enum ModelType: String, Codable, CaseIterable {
    case whisper
    case parakeet
    case groq
}

struct TranscriptionModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let type: ModelType
    let size: String?
    let sizeBytes: Int64?
    let downloadURL: URL?
    let fileName: String?
    let description: String
    let speedRating: Int // 1–5
    let accuracyRating: Int // 1–5
    let languageSupport: String
    let isRecommended: Bool

    init(id: String, name: String, type: ModelType, size: String?, sizeBytes: Int64? = nil, downloadURL: URL?, fileName: String?, description: String, speedRating: Int, accuracyRating: Int, languageSupport: String, isRecommended: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.size = size
        self.sizeBytes = sizeBytes
        self.downloadURL = downloadURL
        self.fileName = fileName
        self.description = description
        self.speedRating = speedRating
        self.accuracyRating = accuracyRating
        self.languageSupport = languageSupport
        self.isRecommended = isRecommended
    }
}

enum TranscriptionModels {
    // NOTE: SwiftWhisper bundles whisper.cpp with WHISPER_N_MEL=80.
    // large-v3 and large-v3-turbo use 128 mel bins and will CRASH.
    // Only models with 80 mel bins are compatible: tiny, base, small, medium, large-v1, large-v2.
    static let all: [TranscriptionModelInfo] = [
        // Recommended models
        TranscriptionModelInfo(
            id: "parakeet-v3",
            name: "Parakeet V3",
            type: .parakeet,
            size: "~494MB",
            sizeBytes: 484_000_000,
            downloadURL: nil,
            fileName: nil,
            description: "Fast and accurate on-device model via CoreML. Supports English and 25+ European languages.",
            speedRating: 5,
            accuracyRating: 5,
            languageSupport: "Multilingual",
            isRecommended: true
        ),
        TranscriptionModelInfo(
            id: "whisper-medium-q5_0",
            name: "Whisper Medium (Q5)",
            type: .whisper,
            size: "~539MB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin"),
            fileName: "ggml-medium-q5_0.bin",
            description: "Near-lossless quality at a fraction of the size. Best balance of accuracy, speed, and disk space.",
            speedRating: 3,
            accuracyRating: 4,
            languageSupport: "Multilingual",
            isRecommended: true
        ),
        TranscriptionModelInfo(
            id: "groq-whisper",
            name: "Groq Whisper",
            type: .groq,
            size: nil,
            downloadURL: nil,
            fileName: nil,
            description: "Cloud-based Whisper via Groq API. Fast and accurate. Requires free API key.",
            speedRating: 5,
            accuracyRating: 5,
            languageSupport: "Multilingual",
            isRecommended: true
        ),
        // Expanded models
        TranscriptionModelInfo(
            id: "whisper-medium",
            name: "Whisper Medium",
            type: .whisper,
            size: "~1.5GB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"),
            fileName: "ggml-medium.bin",
            description: "High accuracy for demanding tasks. Slower on older hardware.",
            speedRating: 2,
            accuracyRating: 4,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-small",
            name: "Whisper Small",
            type: .whisper,
            size: "~466MB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"),
            fileName: "ggml-small.bin",
            description: "Good balance of speed and accuracy for general use.",
            speedRating: 4,
            accuracyRating: 3,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-small-q5_1",
            name: "Whisper Small (Q5)",
            type: .whisper,
            size: "~190MB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin"),
            fileName: "ggml-small-q5_1.bin",
            description: "Quantized small model. Compact with reasonable accuracy.",
            speedRating: 4,
            accuracyRating: 3,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-base",
            name: "Whisper Base",
            type: .whisper,
            size: "~142MB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"),
            fileName: "ggml-base.bin",
            description: "Lightweight model for quick transcriptions.",
            speedRating: 5,
            accuracyRating: 2,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-base-q5_1",
            name: "Whisper Base (Q5)",
            type: .whisper,
            size: "~60MB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin"),
            fileName: "ggml-base-q5_1.bin",
            description: "Tiny footprint for basic transcription needs.",
            speedRating: 5,
            accuracyRating: 2,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-tiny",
            name: "Whisper Tiny",
            type: .whisper,
            size: "~75MB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"),
            fileName: "ggml-tiny.bin",
            description: "Smallest and fastest. Best for quick drafts.",
            speedRating: 5,
            accuracyRating: 1,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-large-v1",
            name: "Whisper Large v1",
            type: .whisper,
            size: "~2.9GB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v1.bin"),
            fileName: "ggml-large-v1.bin",
            description: "Original large model. High accuracy, significant resources required.",
            speedRating: 1,
            accuracyRating: 4,
            languageSupport: "Multilingual"
        ),
        TranscriptionModelInfo(
            id: "whisper-large-v2",
            name: "Whisper Large v2",
            type: .whisper,
            size: "~2.9GB",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2.bin"),
            fileName: "ggml-large-v2.bin",
            description: "Best local accuracy. Requires significant disk space and RAM.",
            speedRating: 1,
            accuracyRating: 5,
            languageSupport: "Multilingual"
        ),
    ]

    /// Models available on the current architecture.
    /// On Intel (x86_64), Parakeet models are excluded because they require Apple Neural Engine.
    static var available: [TranscriptionModelInfo] {
        #if arch(arm64)
        return all
        #else
        return all.filter { $0.type != .parakeet }
        #endif
    }

    /// Recommended models for the current architecture.
    static var recommended: [TranscriptionModelInfo] {
        available.filter { $0.isRecommended }
    }

    /// Non-recommended models for the current architecture (shown under "Show all").
    static var expanded: [TranscriptionModelInfo] {
        available.filter { !$0.isRecommended }
    }

    /// Check if a model requires an API key.
    static func requiresAPIKey(_ model: TranscriptionModelInfo) -> Bool {
        model.type == .groq
    }

    static func find(_ id: String) -> TranscriptionModelInfo? {
        available.first { $0.id == id }
    }

    static func customWhisper(path: String) -> TranscriptionModelInfo {
        TranscriptionModelInfo(
            id: "custom-\(URL(fileURLWithPath: path).lastPathComponent)",
            name: URL(fileURLWithPath: path).lastPathComponent,
            type: .whisper,
            size: nil,
            downloadURL: nil,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            description: "Custom imported Whisper model.",
            speedRating: 3,
            accuracyRating: 3,
            languageSupport: "Unknown"
        )
    }
}
