import Foundation

struct WordReplacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var original: String
    var replacement: String
}

enum WordReplacementStore {
    private static let key = "wordReplacements"

    static func load() -> [WordReplacement] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([WordReplacement].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [WordReplacement]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Apply all word replacements to text (case-insensitive whole-word match).
    static func apply(_ replacements: [WordReplacement], to text: String) -> String {
        var result = text
        for item in replacements where !item.original.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: item.original)
            let pattern = "\\b\(escaped)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: item.replacement
                )
            }
        }
        return result
    }
}
