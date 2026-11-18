import Foundation

extension UserDefaults {
    /// A fresh, empty defaults suite so tests never read or write the user's
    /// real Speaky settings.
    static func isolatedForTesting() -> UserDefaults {
        let name = "speaky.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
