import Foundation

/// What Speaky has learned about how the user speaks: their own words (names,
/// jargon) and the words the engine keeps getting wrong for them.
struct VoiceProfile: Codable, Equatable, Sendable {
    /// One learned mistake: the engine writes `heard` when the user says `meant`.
    struct Correction: Codable, Equatable, Sendable, Identifiable {
        var heard: String          // normalized, lowercase, words separated by single spaces
        var meant: String          // as it should be written
        var count: Int = 1         // times this mistake was seen in training
        /// Times the user deliberately said `heard` in a passage. Any such use means
        /// the phrase is real speech, so replacing it everywhere would be wrong.
        var contradictions: Int = 0
        /// nil = Speaky decides; true/false = the user turned it on or off.
        var userOverride: Bool?
        var lastSeen: Date = .now

        var id: String { heard }
    }

    /// One read-aloud passage.
    struct Session: Codable, Equatable, Sendable {
        var date: Date
        var passageTitle: String
        var wordCount: Int
        /// Words the engine got wrong on its own.
        var rawErrors: Int
        /// Words still wrong after the user's corrections were applied.
        var correctedErrors: Int

        var rawAccuracy: Double { accuracy(errors: rawErrors) }
        var correctedAccuracy: Double { accuracy(errors: correctedErrors) }

        private func accuracy(errors: Int) -> Double {
            guard wordCount > 0 else { return 1 }
            return max(0, 1 - Double(errors) / Double(wordCount))
        }
    }

    var customWords: [String] = []
    var corrections: [Correction] = []
    var sessions: [Session] = []
    /// Index of the next built-in passage to read.
    var nextPassageIndex = 0

    static let maxSessions = 500
}

// MARK: - Storage

/// Reads and writes the profile as JSON in Application Support.
struct VoiceProfileFile: Sendable {
    let url: URL

    static let standard = VoiceProfileFile(
        url: Constants.appSupportPath.appendingPathComponent("VoiceProfile.json")
    )

    func load() -> VoiceProfile {
        guard let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder.voiceProfile.decode(VoiceProfile.self, from: data)
        else { return VoiceProfile() }
        return profile
    }

    func save(_ profile: VoiceProfile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.voiceProfile.encode(profile)
        try data.write(to: url, options: .atomic)
    }
}

private extension JSONDecoder {
    static var voiceProfile: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}

private extension JSONEncoder {
    static var voiceProfile: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
