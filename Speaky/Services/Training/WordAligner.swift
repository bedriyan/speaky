import Foundation

/// Lines up what the user was asked to read with what the engine heard, word by
/// word, and reports the places where they differ.
enum WordAligner {
    /// A word as written, plus the form used for comparison.
    struct Token: Equatable, Sendable {
        let original: String
        let normalized: String
    }

    /// One place where the transcript differs from the reference text.
    struct Difference: Equatable, Sendable {
        /// Reference words (as written) that were expected here. Empty for an extra word.
        let expected: [String]
        /// Transcript words that were heard here. Empty for a missed word.
        let heard: [String]
        /// Index of the first expected word in the reference tokens.
        let expectedStart: Int
    }

    struct Alignment: Equatable, Sendable {
        let reference: [Token]
        let transcript: [Token]
        let differences: [Difference]

        /// Reference words that were not heard correctly.
        var wrongWordCount: Int {
            differences.reduce(0) { $0 + max($1.expected.count, $1.heard.count) }
        }

        /// Share of reference words recognised correctly, 0...1.
        var accuracy: Double {
            guard !reference.isEmpty else { return 1 }
            return max(0, 1 - Double(wrongWordCount) / Double(reference.count))
        }

        /// Indices of reference words that were heard wrong or missed.
        var wrongReferenceIndices: Set<Int> {
            var result = Set<Int>()
            for difference in differences {
                for offset in 0..<difference.expected.count {
                    result.insert(difference.expectedStart + offset)
                }
            }
            return result
        }
    }

    static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { Token(original: strip(String($0)), normalized: normalize(String($0))) }
            .filter { !$0.normalized.isEmpty }
    }

    /// Lowercased, without surrounding punctuation, curly apostrophes made straight.
    static func normalize(_ word: String) -> String {
        strip(word)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
    }

    /// Removes punctuation around a word but keeps inner apostrophes and hyphens.
    static func strip(_ word: String) -> String {
        let edge = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces)
        return word.trimmingCharacters(in: edge)
    }

    static func align(reference: String, transcript: String) -> Alignment {
        let ref = tokenize(reference)
        let hyp = tokenize(transcript)
        var differences = diffRuns(ref.map(\.normalized), hyp.map(\.normalized)).map { run in
            Difference(
                expected: ref[run.reference].map(\.original),
                heard: hyp[run.transcript].map(\.original),
                expectedStart: run.reference.lowerBound
            )
        }
        // "e-mail" vs "email", "Today's" vs "Todays": same word, punctuation only.
        // (A different word split, like "Signit" heard as "sign it", is a real mistake.)
        differences.removeAll { isPunctuationOnly($0) }
        return Alignment(reference: ref, transcript: hyp, differences: differences)
    }

    /// Runs where two word lists differ, from a word-level edit distance.
    static func diffRuns(_ a: [String], _ b: [String]) -> [(reference: Range<Int>, transcript: Range<Int>)] {
        let n = a.count, m = b.count
        var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    cost[i][j] = min(
                        cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1
                    )
                }
            }
        }

        // Walk back from the end, collecting runs of non-matching words.
        var runs: [(reference: Range<Int>, transcript: Range<Int>)] = []
        var i = n, j = m
        var runEnd: (Int, Int)?
        func flush() {
            if let (endI, endJ) = runEnd { runs.append((i..<endI, j..<endJ)) }
            runEnd = nil
        }
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1], cost[i][j] == cost[i - 1][j - 1] {
                flush()
                i -= 1; j -= 1
                continue
            }
            if runEnd == nil { runEnd = (i, j) }
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + 1 {
                i -= 1; j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                i -= 1
            } else {
                j -= 1
            }
        }
        flush()
        return runs.reversed()
    }

    static func isPunctuationOnly(_ difference: Difference) -> Bool {
        guard !difference.expected.isEmpty, difference.expected.count == difference.heard.count else { return false }
        return squashed(difference.expected) == squashed(difference.heard)
    }

    static func squashed(_ words: [String]) -> String {
        words.map(normalize).joined().filter { $0.isLetter || $0.isNumber }
    }
}
