import SwiftUI
import SwiftData
import AVFoundation
import AppKit

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.date, order: .reverse) private var transcriptions: [Transcription]
    @State private var searchText = ""
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var reTranscribingIDs: Set<UUID> = []
    @State private var reTranscribeErrors: [UUID: String] = [:]

    private var filtered: [Transcription] {
        if searchText.isEmpty { return transcriptions }
        return transcriptions.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private var groupedByDay: [(key: String, items: [Transcription])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { item -> String in
            if calendar.isDateInToday(item.date) {
                return "Today"
            } else if calendar.isDateInYesterday(item.date) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE, d MMMM"
                return formatter.string(from: item.date)
            }
        }

        // Sort groups by the most recent item date in each group
        return grouped.map { (key: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                guard let lDate = lhs.items.first?.date, let rDate = rhs.items.first?.date else { return false }
                return lDate > rDate
            }
    }

    var body: some View {
        Group {
            if transcriptions.isEmpty {
                ContentUnavailableView {
                    Label("No Transcriptions", systemImage: "waveform")
                        .foregroundStyle(Theme.amber)
                } description: {
                    Text("Press the global hotkey or click the menu bar icon to start recording.")
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                List {
                    ForEach(groupedByDay, id: \.key) { group in
                        Section {
                            ForEach(group.items) { item in
                                TranscriptionRow(
                                    item: item,
                                    isPlaying: playingID == item.id,
                                    isReTranscribing: reTranscribingIDs.contains(item.id),
                                    errorMessage: reTranscribeErrors[item.id],
                                    onTogglePlay: { togglePlayback(item) },
                                    onReTranscribe: { reTranscribe(item) },
                                    onRevealInFinder: { revealInFinder(item) }
                                )
                                .contextMenu {
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.text, forType: .string)
                                    }
                                    if item.audioFileURL != nil {
                                        Button("Re-transcribe") {
                                            reTranscribe(item)
                                        }
                                    }
                                    if hasAudioFile(item) {
                                        Button("Reveal in Finder") {
                                            revealInFinder(item)
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        deleteTranscription(item)
                                    }
                                }
                            }
                            .onDelete { indices in
                                for index in indices {
                                    deleteTranscription(group.items[index])
                                }
                            }
                        } header: {
                            Text(group.key)
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search transcriptions")
            }
        }
        .navigationTitle("History")
    }

    private func hasAudioFile(_ item: Transcription) -> Bool {
        guard let path = item.audioFileURL else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private func revealInFinder(_ item: Transcription) {
        guard let path = item.audioFileURL, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    private func togglePlayback(_ item: Transcription) {
        if playingID == item.id {
            audioPlayer?.stop()
            audioPlayer = nil
            playingID = nil
            return
        }

        guard let path = item.audioFileURL else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            playingID = item.id
        } catch {
            playingID = nil
        }
    }

    private func reTranscribe(_ item: Transcription) {
        guard let path = item.audioFileURL else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard !reTranscribingIDs.contains(item.id) else { return }

        reTranscribingIDs.insert(item.id)
        reTranscribeErrors.removeValue(forKey: item.id)

        Task {
            defer { reTranscribingIDs.remove(item.id) }
            do {
                let result = try await appState.transcribeExternalAudio(
                    fileURL: url,
                    modelID: appState.settings.selectedModelID,
                    language: appState.settings.language
                )
                item.text = result
                item.date = Date()
                item.modelID = appState.settings.selectedModelID
                try? modelContext.save()
            } catch {
                reTranscribeErrors[item.id] = error.localizedDescription
            }
        }
    }

    private func deleteTranscription(_ item: Transcription) {
        if let path = item.audioFileURL {
            try? FileManager.default.removeItem(atPath: path)
        }
        modelContext.delete(item)
    }
}

struct TranscriptionRow: View {
    let item: Transcription
    let isPlaying: Bool
    let isReTranscribing: Bool
    var errorMessage: String? = nil
    let onTogglePlay: () -> Void
    let onReTranscribe: () -> Void
    var onRevealInFinder: (() -> Void)? = nil

    private var hasAudio: Bool {
        guard let path = item.audioFileURL else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Play button
            if hasAudio {
                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.amber)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .lineLimit(3)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 8) {
                    Text(formatTimestamp(item.date))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Text("·")
                        .foregroundStyle(Theme.textTertiary)

                    Text(formatDuration(item.duration))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Text("·")
                        .foregroundStyle(Theme.textTertiary)

                    Text(item.modelID)
                        .font(.caption)
                        .foregroundStyle(Theme.amber.opacity(0.7))

                    if hasAudio {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if let errorMessage {
                    Text("Re-transcription failed: \(errorMessage)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            // Inline action buttons
            HStack(spacing: 6) {
                if hasAudio {
                    if isReTranscribing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                    } else {
                        Button(action: onReTranscribe) {
                            Image(systemName: "arrow.trianglehead.2.counterclockwise")
                                .font(.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Re-transcribe")
                    }

                    if let onRevealInFinder {
                        Button(action: onRevealInFinder) {
                            Image(systemName: "folder")
                                .font(.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }

                CopyButton(text: item.text)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return mins == 1 ? "1 min ago" : "\(mins) min ago"
        } else if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Today \(formatter.string(from: date))"
        } else if Calendar.current.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM, HH:mm"
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

private struct CopyButton: View {
    let text: String
    @State private var justCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                justCopied = false
            }
        } label: {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.body)
                .foregroundStyle(justCopied ? Theme.success : Theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help("Copy text")
    }
}
