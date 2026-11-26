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
    /// Words the user wants recognised (their names, products, jargon, and words
    /// learned in training). Engines use them as a hint where they can.
    func setVocabulary(_ words: [String]) async
}

extension TranscriptionEngine {
    // Default no-op for cloud engines (Groq) that have no local model to prime
    func warmUp() async throws {}
    func setVocabulary(_ words: [String]) async {}
}

enum VocabularyPrompt {
    /// A short "prompt" for Whisper-style engines. Whisper treats the prompt as
    /// preceding text, so listing the words makes it prefer those spellings.
    /// Kept well under Whisper's 224-token prompt limit.
    static func make(_ words: [String], maxCharacters: Int = 600) -> String? {
        var parts: [String] = []
        var length = 0
        for word in words {
            let addition = word.count + 2
            if length + addition > maxCharacters { break }
            parts.append(word)
            length += addition
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
    }
}
