import Foundation
import SwiftData
import AVFoundation
import os

private let logger = Logger.speaky(category: "RecordingRecovery")

/// Finds saved recordings that have no history entry (for example after the
/// history store was reset or lost) and re-transcribes them back into history.
///
/// Audio files are only read, never moved or deleted. Recovered entries use
/// the recording file's creation date, so they land in the right place in history.
/// Running it twice is harmless: files that already have an entry are skipped.
@MainActor
enum RecordingRecovery {
    struct Progress: Equatable {
        var done = 0
        var total = 0
        var recovered = 0
        var failed = 0
    }

    /// Recordings in `directory` that no history entry points to, oldest first.
    static func orphanedRecordings(in directory: URL, context: ModelContext) throws -> [URL] {
        let referenced = Set(
            try context.fetch(FetchDescriptor<Transcription>())
                .compactMap(\.audioFileURL)
                .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        )
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .filter { !referenced.contains($0.resolvingSymlinksInPath().path) }
            .sorted { creationDate(of: $0) < creationDate(of: $1) }
    }

    /// Re-transcribe `urls` and insert a history entry for each. Saves after
    /// every file so progress survives a quit. `transcribe` returns the text.
    static func recover(
        _ urls: [URL],
        modelID: String,
        language: String,
        context: ModelContext,
        transcribe: (URL) async throws -> String,
        onProgress: (Progress) -> Void = { _ in }
    ) async -> Progress {
        var progress = Progress(total: urls.count)
        onProgress(progress)
        for url in urls {
            if Task.isCancelled { break }
            do {
                let text = try await transcribe(url)
                let entry = Transcription(
                    text: text,
                    duration: duration(of: url),
                    modelID: modelID,
                    language: language,
                    audioFileURL: url.path
                )
                entry.date = creationDate(of: url)
                context.insert(entry)
                try context.save()
                progress.recovered += 1
            } catch {
                logger.warning("Could not recover \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                progress.failed += 1
            }
            progress.done += 1
            onProgress(progress)
        }
        logger.info("Recovered \(progress.recovered) of \(progress.total) recordings (\(progress.failed) failed)")
        return progress
    }

    static func creationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
