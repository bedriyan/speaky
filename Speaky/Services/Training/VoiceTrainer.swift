import Foundation
import os

private let logger = Logger.speaky(category: "VoiceTrainer")

/// Runs voice training: picks what to read, learns from each reading, and keeps
/// the user's `VoiceProfile` up to date on disk.
@Observable
@MainActor
final class VoiceTrainer {
    enum Phase: Equatable {
        case ready
        case reading
        case transcribing
        case reviewed
        case failed(String)
    }

    struct Review: Equatable {
        let alignment: WordAligner.Alignment
        let heard: String
        /// Accuracy once the corrections learned so far are applied.
        let correctedAccuracy: Double
        /// Mistakes Speaky had not seen before this reading.
        let newMistakes: Int
    }

    private(set) var profile: VoiceProfile
    private(set) var passage: TrainingPassage
    var phase: Phase = .ready
    private(set) var review: Review?
    /// Whether the training page is on screen (the hotkey then reads the passage).
    var isOpen = false

    var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    @ObservationIgnored let learner: TrainingLearner
    @ObservationIgnored private let file: VoiceProfileFile
    /// Called after every change to the profile.
    @ObservationIgnored var onProfileChange: (() -> Void)?

    init(file: VoiceProfileFile = .standard, learner: TrainingLearner = .live) {
        self.file = file
        self.learner = learner
        let profile = file.load()
        self.profile = profile
        self.passage = TrainingPassages.next(for: profile, practiceWords: Self.practiceWords(in: profile))
    }

    // MARK: - Reading

    /// Learn from what the engine heard while the user read the current passage.
    func finishReading(heard: String) {
        let before = Set(profile.corrections.map(\.heard))
        let (updated, alignment) = learner.learn(reference: passage.text, transcript: heard, into: profile)
        var profile = updated

        let corrector = PersonalCorrector(corrections: learner.activeCorrections(in: profile))
        let corrected = WordAligner.align(reference: passage.text, transcript: corrector.apply(heard))

        profile.sessions.append(.init(
            date: .now,
            passageTitle: passage.title,
            wordCount: alignment.reference.count,
            rawErrors: alignment.wrongWordCount,
            correctedErrors: corrected.wrongWordCount
        ))
        if profile.sessions.count > VoiceProfile.maxSessions {
            profile.sessions.removeFirst(profile.sessions.count - VoiceProfile.maxSessions)
        }

        review = Review(
            alignment: alignment,
            heard: heard,
            correctedAccuracy: corrected.accuracy,
            newMistakes: profile.corrections.filter { !before.contains($0.heard) }.count
        )
        phase = .reviewed
        commit(profile)
        logger.info("Training reading: \(alignment.wrongWordCount) of \(alignment.reference.count) words wrong")
    }

    func readingFailed(_ message: String) {
        phase = .failed(message)
    }

    func readAgain() {
        review = nil
        phase = .ready
    }

    /// Move on to the next passage (also used to skip one).
    func nextPassage() {
        var profile = profile
        if passage.kind == .builtIn { profile.nextPassageIndex += 1 }
        var next = TrainingPassages.next(for: profile, practiceWords: Self.practiceWords(in: profile))
        if next.id == passage.id && next.kind != .builtIn {
            // Skipping a special passage: go to the next built-in one instead.
            next = TrainingPassages.builtIn[profile.nextPassageIndex % TrainingPassages.builtIn.count]
        }
        passage = next
        review = nil
        phase = .ready
        commit(profile)
    }

    // MARK: - Your words

    @discardableResult
    func addCustomWords(_ input: String) -> Int {
        var profile = profile
        var added = 0
        for raw in input.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, word.count <= 60,
                  !profile.customWords.contains(where: { $0.lowercased() == word.lowercased() })
            else { continue }
            profile.customWords.append(word)
            added += 1
        }
        if added > 0 { commit(profile) }
        return added
    }

    func removeCustomWord(_ word: String) {
        var profile = profile
        profile.customWords.removeAll { $0 == word }
        commit(profile)
    }

    // MARK: - Learned corrections

    func isActive(_ correction: VoiceProfile.Correction) -> Bool {
        learner.isActive(correction, in: profile)
    }

    func setActive(_ correction: VoiceProfile.Correction, _ active: Bool) {
        var profile = profile
        guard let index = profile.corrections.firstIndex(where: { $0.heard == correction.heard }) else { return }
        // Going back to what Speaky would choose itself clears the override.
        var automatic = profile.corrections[index]
        automatic.userOverride = nil
        profile.corrections[index].userOverride = learner.isActive(automatic, in: profile) == active ? nil : active
        commit(profile)
    }

    func deleteCorrection(_ correction: VoiceProfile.Correction) {
        var profile = profile
        profile.corrections.removeAll { $0.heard == correction.heard }
        commit(profile)
    }

    func resetTraining() {
        var profile = VoiceProfile()
        profile.customWords = self.profile.customWords
        review = nil
        phase = .ready
        passage = TrainingPassages.builtIn[0]
        commit(profile)
    }

    // MARK: - Progress

    var sessionCount: Int { profile.sessions.count }
    var activeCorrectionCount: Int { learner.activeCorrections(in: profile).count }

    /// Average accuracy of the first readings, before Speaky had learned anything.
    var startingAccuracy: Double? {
        let first = profile.sessions.prefix(3)
        guard !first.isEmpty else { return nil }
        return first.map(\.rawAccuracy).reduce(0, +) / Double(first.count)
    }

    /// Average accuracy of the latest readings with corrections applied.
    var currentAccuracy: Double? {
        let last = profile.sessions.suffix(3)
        guard !last.isEmpty else { return nil }
        return last.map(\.correctedAccuracy).reduce(0, +) / Double(last.count)
    }

    /// Corrections for display: most-seen first.
    var sortedCorrections: [VoiceProfile.Correction] {
        profile.corrections.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
    }

    // MARK: - Private

    private static func practiceWords(in profile: VoiceProfile) -> [String] {
        var seen = Set<String>()
        return profile.corrections
            .sorted { $0.count > $1.count }
            .map(\.meant)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private func commit(_ profile: VoiceProfile) {
        self.profile = profile
        do {
            try file.save(profile)
        } catch {
            logger.error("Could not save voice profile: \(error.localizedDescription, privacy: .public)")
        }
        onProfileChange?()
    }
}
