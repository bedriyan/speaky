import Testing
import Foundation
import SwiftData
import AVFoundation
@testable import Speaky

@Suite("RecordingRecovery")
@MainActor
struct RecordingRecoveryTests {
    struct Fixture {
        let dir: URL
        let context: ModelContext
        let container: ModelContainer
    }

    private func makeFixture() throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speaky-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let container = try ModelContainer(for: Transcription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return Fixture(dir: dir, context: container.mainContext, container: container)
    }

    /// Writes a real 16 kHz mono WAV of `seconds` length with the given creation date.
    @discardableResult
    private func writeWAV(_ name: String, in dir: URL, seconds: Double, created: Date) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(16000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
        try FileManager.default.setAttributes([.creationDate: created, .modificationDate: created], ofItemAtPath: url.path)
        return url
    }

    @Test("finds only recordings without a history entry, oldest first")
    func findsOrphans() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let kept = try writeWAV("recording_kept.wav", in: f.dir, seconds: 1, created: Date(timeIntervalSince1970: 3000))
        try writeWAV("recording_new.wav", in: f.dir, seconds: 1, created: Date(timeIntervalSince1970: 2000))
        try writeWAV("recording_old.wav", in: f.dir, seconds: 1, created: Date(timeIntervalSince1970: 1000))
        try Data().write(to: f.dir.appendingPathComponent("notes.txt"))
        f.context.insert(Transcription(text: "kept", duration: 1, modelID: "m", language: "auto", audioFileURL: kept.path))
        try f.context.save()

        let orphans = try RecordingRecovery.orphanedRecordings(in: f.dir, context: f.context)
        #expect(orphans.map(\.lastPathComponent) == ["recording_old.wav", "recording_new.wav"])
    }

    @Test("recovers orphans with their original dates and durations, and is idempotent")
    func recovers() async throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let url = try writeWAV("recording_a.wav", in: f.dir, seconds: 2, created: created)
        let before = try Data(contentsOf: url)

        let orphans = try RecordingRecovery.orphanedRecordings(in: f.dir, context: f.context)
        var updates: [RecordingRecovery.Progress] = []
        let result = await RecordingRecovery.recover(
            orphans, modelID: "parakeet-v3", language: "auto", context: f.context,
            transcribe: { _ in "hello world" },
            onProgress: { updates.append($0) }
        )
        #expect(result == .init(done: 1, total: 1, recovered: 1, failed: 0))
        #expect(updates.first == .init(done: 0, total: 1, recovered: 0, failed: 0))

        let entries = try f.context.fetch(FetchDescriptor<Transcription>())
        #expect(entries.count == 1)
        #expect(entries[0].text == "hello world")
        #expect(entries[0].audioFileURL.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() } == url.resolvingSymlinksInPath())
        #expect(abs(entries[0].date.timeIntervalSince(created)) < 1)
        #expect(abs(entries[0].duration - 2) < 0.01)

        // Audio untouched, and a second scan finds nothing left to do.
        #expect(try Data(contentsOf: url) == before)
        #expect(try RecordingRecovery.orphanedRecordings(in: f.dir, context: f.context).isEmpty)
    }

    @Test("a failing file is counted and skipped without stopping the rest")
    func failuresCounted() async throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let bad = try writeWAV("recording_bad.wav", in: f.dir, seconds: 1, created: Date(timeIntervalSince1970: 1))
        try writeWAV("recording_good.wav", in: f.dir, seconds: 1, created: Date(timeIntervalSince1970: 2))
        struct Boom: Error {}

        let result = await RecordingRecovery.recover(
            try RecordingRecovery.orphanedRecordings(in: f.dir, context: f.context),
            modelID: "m", language: "auto", context: f.context,
            transcribe: { url in if url.lastPathComponent == bad.lastPathComponent { throw Boom() }; return "ok" }
        )
        #expect(result.recovered == 1)
        #expect(result.failed == 1)
        #expect(FileManager.default.fileExists(atPath: bad.path))
        // The failed one is still offered next time.
        #expect(try RecordingRecovery.orphanedRecordings(in: f.dir, context: f.context).map(\.lastPathComponent) == [bad.lastPathComponent])
    }
}
