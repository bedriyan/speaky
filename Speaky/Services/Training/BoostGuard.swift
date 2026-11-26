import Foundation

/// Keeps vocabulary boosting from over-reaching.
///
/// FluidAudio's CTC boosting fixes a misheard name ("Signet" -> "Signit") but
/// will also glue ordinary words together when they sound like a boosted term
/// ("please sign it" -> "please Signit"). This compares the boosted text with
/// what the engine originally heard and keeps only the safe changes: a single
/// misheard word becoming a boosted term. Everything else stays as heard,
/// including the engine's own punctuation.
enum BoostGuard {
    static func filter(original: String, boosted: String) -> String {
        let originalWords = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let boostedWords = boosted.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !originalWords.isEmpty, boosted != original else { return boosted }

        let runs = WordAligner.diffRuns(
            originalWords.map(WordAligner.normalize),
            boostedWords.map(WordAligner.normalize)
        )
        var result: [String] = []
        var position = 0
        for run in runs {
            result += originalWords[position..<run.reference.lowerBound]
            let heard = Array(originalWords[run.reference])
            let replacement = Array(boostedWords[run.transcript])
            if accept(heard: heard, replacement: replacement) {
                // Keep the punctuation the engine put after the word.
                let trailing = String(heard[0].reversed().prefix { $0.isPunctuation }.reversed())
                result.append(WordAligner.strip(replacement[0]) + trailing)
            } else {
                result += heard
            }
            position = run.reference.upperBound
        }
        result += originalWords[position...]
        return result.joined(separator: " ")
    }

    private static func accept(heard: [String], replacement: [String]) -> Bool {
        // One word for one word only. Merging several words ("sign it") or
        // splitting one is where boosting goes wrong.
        guard heard.count == 1, replacement.count == 1 else { return false }
        return !WordAligner.normalize(heard[0]).isEmpty && !WordAligner.normalize(replacement[0]).isEmpty
    }
}
