import Foundation

@Observable
@MainActor
final class UsageStatistics {
    private let defaults = UserDefaults.standard

    private(set) var totalTranscriptions: Int {
        didSet { defaults.set(totalTranscriptions, forKey: "stats_totalTranscriptions") }
    }
    private(set) var totalRecordedSeconds: Double {
        didSet { defaults.set(totalRecordedSeconds, forKey: "stats_totalRecordedSeconds") }
    }
    private(set) var totalWordsTranscribed: Int {
        didSet { defaults.set(totalWordsTranscribed, forKey: "stats_totalWordsTranscribed") }
    }

    private(set) var dailyStats: [String: DailyStat] {
        didSet { saveDailyStats() }
    }

    var totalRecordedMinutes: Double {
        totalRecordedSeconds / 60.0
    }

    var todayStats: DailyStat {
        dailyStats[Self.todayKey] ?? DailyStat()
    }

    init() {
        self.totalTranscriptions = defaults.integer(forKey: "stats_totalTranscriptions")
        self.totalRecordedSeconds = defaults.double(forKey: "stats_totalRecordedSeconds")
        self.totalWordsTranscribed = defaults.integer(forKey: "stats_totalWordsTranscribed")
        self.dailyStats = Self.loadDailyStats()
    }

    func recordTranscription(text: String, durationSeconds: Double) {
        let wordCount = text.split(separator: " ").count

        totalTranscriptions += 1
        totalRecordedSeconds += durationSeconds
        totalWordsTranscribed += wordCount

        let key = Self.todayKey
        var today = dailyStats[key] ?? DailyStat()
        today.transcriptions += 1
        today.recordedSeconds += durationSeconds
        today.wordsTranscribed += wordCount
        dailyStats[key] = today
    }

    // MARK: - Daily Stats Persistence

    struct DailyStat: Codable {
        var transcriptions: Int = 0
        var recordedSeconds: Double = 0
        var wordsTranscribed: Int = 0

        var recordedMinutes: Double { recordedSeconds / 60.0 }
    }

    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func loadDailyStats() -> [String: DailyStat] {
        guard let data = UserDefaults.standard.data(forKey: "stats_daily") else { return [:] }
        return (try? JSONDecoder().decode([String: DailyStat].self, from: data)) ?? [:]
    }

    private func saveDailyStats() {
        guard let data = try? JSONEncoder().encode(dailyStats) else { return }
        defaults.set(data, forKey: "stats_daily")
    }
}
