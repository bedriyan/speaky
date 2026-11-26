import AppKit
import Foundation

/// Turns a read-aloud passage and what the engine heard into lessons stored in
/// the user's `VoiceProfile`, and decides which lessons are safe to apply.
struct TrainingLearner: Sendable {
    /// Whether a single lowercase word is ordinary English. Injected for tests.
    let isDictionaryWord: @Sendable (String) -> Bool

    static let live = TrainingLearner(isDictionaryWord: SystemDictionary.contains)

    /// Longest phrases learned from one mistake. Longer runs are usually the
    /// engine losing track, not a word it consistently mishears.
    static let maxExpectedWords = 3
    static let maxHeardWords = 4

    /// Record what this reading shows and return the updated profile.
    func learn(reference: String, transcript: String, into profile: VoiceProfile) -> (VoiceProfile, WordAligner.Alignment) {
        var profile = profile
        let alignment = WordAligner.align(reference: reference, transcript: transcript)

        for difference in alignment.differences {
            guard !difference.expected.isEmpty, !difference.heard.isEmpty,
                  difference.expected.count <= Self.maxExpectedWords,
                  difference.heard.count <= Self.maxHeardWords
            else { continue }
            let heard = Self.key(difference.heard)
            let meant = difference.expected.joined(separator: " ")
            guard !heard.isEmpty, heard != Self.key(difference.expected) else { continue }

            if let index = profile.corrections.firstIndex(where: { $0.heard == heard }) {
                if profile.corrections[index].meant.lowercased() == meant.lowercased() {
                    profile.corrections[index].count += 1
                } else {
                    // Heard the same thing for a different word: it's ambiguous.
                    profile.corrections[index].contradictions += 1
                }
                profile.corrections[index].lastSeen = .now
            } else {
                profile.corrections.append(.init(heard: heard, meant: meant))
            }
        }

        // The user said these phrases on purpose, so they are real speech.
        let spoken = " " + alignment.reference.map(\.normalized).joined(separator: " ") + " "
        for index in profile.corrections.indices where spoken.contains(" \(profile.corrections[index].heard) ") {
            profile.corrections[index].contradictions += 1
        }
        return (profile, alignment)
    }

    /// Whether a learned correction should be applied to dictation.
    ///
    /// Fixing a non-word the engine invented is always safe. Replacing real
    /// words is only done for the user's own names and jargon, once seen twice.
    /// Swapping one common word for another ("there" -> "their") depends on
    /// context, so that is left to the user to turn on.
    func isActive(_ correction: VoiceProfile.Correction, in profile: VoiceProfile) -> Bool {
        if let override = correction.userOverride { return override }
        guard correction.contradictions == 0 else { return false }
        if !allDictionaryWords(correction.heard) { return true }
        let isCustom = profile.customWords.contains { $0.lowercased() == correction.meant.lowercased() }
        let meantIsJargon = isCustom || !allDictionaryWords(correction.meant.lowercased())
        return meantIsJargon && correction.count >= 2
    }

    func activeCorrections(in profile: VoiceProfile) -> [VoiceProfile.Correction] {
        profile.corrections.filter { isActive($0, in: profile) }
    }

    /// Words worth hinting to the engine: the user's own words, plus learned
    /// targets that aren't ordinary English (names, product names, jargon).
    func vocabulary(for profile: VoiceProfile) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let learned = activeCorrections(in: profile).map(\.meant)
            .filter { !allDictionaryWords($0.lowercased()) }
        for word in profile.customWords + learned {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    func allDictionaryWords(_ phrase: String) -> Bool {
        phrase.split(separator: " ").allSatisfy { word in
            let w = WordAligner.normalize(String(word))
            return w.isEmpty || isDictionaryWord(w)
        }
    }

    static func key(_ words: [String]) -> String {
        words.map(WordAligner.normalize).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The macOS spelling dictionary, used to tell real words from engine inventions.
enum SystemDictionary {
    @Sendable static func contains(_ word: String) -> Bool {
        if word.count <= 1 { return true }
        let check: () -> Bool = {
            let checker = NSSpellChecker.shared
            let range = checker.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            return range.location == NSNotFound
        }
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }
}

/// Applies the user's learned corrections to dictated text.
struct PersonalCorrector: Sendable {
    private let rules: [(regex: NSRegularExpression, meant: String)]

    static let none = PersonalCorrector(corrections: [])

    init(corrections: [VoiceProfile.Correction]) {
        rules = corrections
            .sorted { $0.heard.count > $1.heard.count } // longest phrase first
            .compactMap { correction in
                let words = correction.heard.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
                guard !words.isEmpty else { return nil }
                let pattern = "(?<![\\p{L}\\p{N}'])" + words.joined(separator: "[\\s,]+") + "(?![\\p{L}\\p{N}'])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                return (regex, correction.meant)
            }
    }

    var isEmpty: Bool { rules.isEmpty }

    func apply(_ text: String) -> String {
        var result = text
        for rule in rules {
            let matches = rule.regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: Self.matchCase(rule.meant, to: result[range]))
            }
        }
        return result
    }

    /// Keep a sentence-initial capital: "Their" stays capitalised when it replaces "There".
    private static func matchCase(_ meant: String, to original: Substring) -> String {
        guard let first = original.first, first.isUppercase,
              let meantFirst = meant.first, meantFirst.isLowercase
        else { return meant }
        return meantFirst.uppercased() + meant.dropFirst()
    }
}
