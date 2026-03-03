import Foundation

struct TranscriptionResult: Sendable {
    let text: String
    let language: String?
    let duration: TimeInterval
    let segments: [Segment]

    struct Segment: Sendable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case invalidAudioFile
    case engineError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Model not loaded"
        case .invalidAudioFile: "Invalid audio file"
        case .engineError(let msg): "Engine error: \(msg)"
        }
    }
}

protocol TranscriptionEngine: AnyObject, Sendable {
    func transcribe(audioFileURL: URL, language: String) async throws -> TranscriptionResult
    func cleanup() async
    /// Pre-load models into memory so first transcription is instant.
    func warmUp() async throws
}

extension TranscriptionEngine {
    // Default no-op for engines that load eagerly (Whisper, Groq)
    func warmUp() async throws {}
}
