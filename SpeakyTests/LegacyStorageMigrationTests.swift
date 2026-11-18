import Testing
import Foundation
import SwiftData
import SQLite3
@testable import Speaky

@Suite("LegacyStorageMigration")
struct LegacyStorageMigrationTests {

    // MARK: Settings

    @Test("copies legacy settings once and keeps values already set")
    func defaultsCopiedOnce() {
        let defaults = UserDefaults.isolatedForTesting()
        defaults.set("en", forKey: "language")
        let legacy: [String: Any] = ["language": "ar", "backgroundAudioMode": "muteSystemAudio", "selectedAudioDevice": 115]

        let copied = LegacyStorageMigration.migrateDefaults(legacy: legacy, into: defaults)
        #expect(copied == 2)
        #expect(defaults.string(forKey: "language") == "en")
        #expect(defaults.string(forKey: "backgroundAudioMode") == "muteSystemAudio")
        #expect(defaults.integer(forKey: "selectedAudioDevice") == 115)

        // A later change by the user must not be overwritten by a second run.
        defaults.set("pauseMedia", forKey: "backgroundAudioMode")
        #expect(LegacyStorageMigration.migrateDefaults(legacy: legacy, into: defaults) == 0)
        #expect(defaults.string(forKey: "backgroundAudioMode") == "pauseMedia")
    }

    @Test("migrated settings are what AppSettings loads")
    func appSettingsSeesMigratedValues() {
        let defaults = UserDefaults.isolatedForTesting()
        LegacyStorageMigration.migrateDefaults(legacy: ["backgroundAudioMode": "muteSystemAudio", "soundEffectsEnabled": false], into: defaults)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.backgroundAudioMode == .muteSystemAudio)
        #expect(settings.soundEffectsEnabled == false)
    }

    // MARK: History store

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speaky-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeLegacyStore(at url: URL, texts: [String]) throws {
        let container = try ModelContainer(for: Transcription.self, configurations: ModelConfiguration(url: url))
        let context = container.mainContext
        for text in texts {
            context.insert(Transcription(text: text, duration: 1, modelID: "parakeet-v3", language: "auto"))
        }
        try context.save()
    }

    @Test("copies Speaky history to the new store and leaves the old one in place")
    @MainActor
    func historyCopied() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent("default.store")
        let new = dir.appendingPathComponent("Speaky/History.store")
        try makeLegacyStore(at: legacy, texts: ["one", "two", "three"])

        #expect(LegacyStorageMigration.migrateHistoryStore(from: legacy, to: new) == .copied)
        #expect(FileManager.default.fileExists(atPath: legacy.path))

        let container = try ModelContainer(for: Transcription.self, configurations: ModelConfiguration(url: new))
        let items = try container.mainContext.fetch(FetchDescriptor<Transcription>())
        #expect(Set(items.map(\.text)) == ["one", "two", "three"])

        // Second launch: nothing to do.
        #expect(LegacyStorageMigration.migrateHistoryStore(from: legacy, to: new) == .notNeeded)
    }

    @Test("does not touch a default.store that belongs to another app")
    func foreignStoreIgnored() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent("default.store")
        var db: OpaquePointer?
        sqlite3_open(legacy.path, &db)
        sqlite3_exec(db, "CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY);", nil, nil, nil)
        sqlite3_close(db)
        let new = dir.appendingPathComponent("Speaky/History.store")

        #expect(LegacyStorageMigration.migrateHistoryStore(from: legacy, to: new) == .notSpeakys)
        #expect(!FileManager.default.fileExists(atPath: new.path))
    }

    @Test("fresh install: no legacy store, nothing to do")
    func noLegacyStore() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(LegacyStorageMigration.migrateHistoryStore(
            from: dir.appendingPathComponent("default.store"),
            to: dir.appendingPathComponent("Speaky/History.store")
        ) == .notNeeded)
    }
}

@Suite("AppSettings auto-unload")
struct AutoUnloadSettingTests {
    @Test("the old 300 s default is migrated to never, once")
    func legacyDefaultMigratedOnce() {
        let defaults = UserDefaults.isolatedForTesting()
        defaults.set(300.0, forKey: "autoUnloadTimeout")
        #expect(AppSettings(defaults: defaults).autoUnloadTimeout == 0)
    }

    @Test("choosing 5 minutes survives a relaunch")
    func fiveMinutesPersists() {
        let defaults = UserDefaults.isolatedForTesting()
        let first = AppSettings(defaults: defaults)
        first.engineUnloadOption = .fiveMinutes
        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.engineUnloadOption == .fiveMinutes)
    }
}
