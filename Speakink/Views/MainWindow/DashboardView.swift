import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Transcription.date, order: .reverse) private var transcriptions: [Transcription]

    private var recentTranscriptions: [Transcription] {
        Array(transcriptions.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status header
                statusHeader

                // Today section
                sectionHeader("Today")
                statTiles(
                    transcriptions: appState.usageStats.todayStats.transcriptions,
                    minutes: appState.usageStats.todayStats.recordedMinutes,
                    words: appState.usageStats.todayStats.wordsTranscribed,
                    background: Theme.bgCard,
                    numberColor: Theme.amber
                )

                // All Time section
                sectionHeader("All Time")
                statTiles(
                    transcriptions: appState.usageStats.totalTranscriptions,
                    minutes: appState.usageStats.totalRecordedMinutes,
                    words: appState.usageStats.totalWordsTranscribed,
                    background: Theme.bgElevated,
                    numberColor: Theme.amberLight
                )

                // Recent section
                if !recentTranscriptions.isEmpty {
                    sectionHeader("Recent")
                    recentSection
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Theme.amber)
                .frame(width: 3)

            HStack(spacing: 8) {
                Text(appState.settings.selectedModel.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)

                Text("·")
                    .foregroundStyle(Theme.textTertiary)

                Text(stateLabel)
                    .font(.subheadline)
                    .foregroundStyle(stateColor)

                Spacer()

                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 36)
    }

    private var stateLabel: String {
        switch appState.state {
        case .idle: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .error: "Error"
        }
    }

    private var stateColor: Color {
        switch appState.state {
        case .idle: Theme.textSecondary
        case .recording: Theme.recording
        case .transcribing: Theme.amber
        case .error: .red
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: Date())
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.textPrimary)
    }

    // MARK: - Stat Tiles

    private func statTiles(transcriptions: Int, minutes: Double, words: Int, background: Color, numberColor: Color) -> some View {
        HStack(spacing: 12) {
            statTile(value: "\(transcriptions)", label: "Transcriptions", background: background, numberColor: numberColor)
            statTile(value: String(format: "%.1f", minutes), label: "Minutes", background: background, numberColor: numberColor)
            statTile(value: "\(words)", label: "Words", background: background, numberColor: numberColor)
        }
    }

    private func statTile(value: String, label: String, background: Color, numberColor: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(numberColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(background)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.amber.opacity(0.4))
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(spacing: 0) {
            ForEach(recentTranscriptions) { item in
                HStack(spacing: 10) {
                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(relativeTime(item.date))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if item.id != recentTranscriptions.last?.id {
                    Divider()
                        .padding(.horizontal, 12)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.bgCard)
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
        let days = Int(interval / 86400)
        return "\(days)d ago"
    }
}
