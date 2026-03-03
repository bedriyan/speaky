import Foundation

enum TextCleanupService {
    private static let fillerPatterns: [String] = [
        "\\bum\\b", "\\buh\\b", "\\blike\\b,?\\s*",
        "\\byou know\\b,?\\s*", "\\bbasically\\b,?\\s*",
        "\\bactually\\b,?\\s*", "\\bsort of\\b,?\\s*",
        "\\bkind of\\b,?\\s*", "\\bi mean\\b,?\\s*",
    ]

    /// Apply all cleanup steps to transcribed text.
    static func clean(_ text: String) -> String {
        var result = text

        // Remove filler words (case-insensitive)
        for pattern in fillerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Fix double/triple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Auto-capitalize first letter of sentences
        result = capitalizeSentences(result)

        // Trim trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    private static func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = Array(text)
        var capitalizeNext = true

        for i in result.indices {
            if capitalizeNext && result[i].isLetter {
                result[i] = Character(result[i].uppercased())
                capitalizeNext = false
            } else if result[i] == "." || result[i] == "!" || result[i] == "?" {
                capitalizeNext = true
            }
        }

        return String(result)
    }
}
