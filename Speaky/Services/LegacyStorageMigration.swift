import Foundation
import SQLite3
import os

private let logger = Logger.speaky(category: "LegacyStorageMigration")

/// Moves settings and history out of the locations Speaky used before it had a
/// bundle identifier:
///
/// - Settings lived in the `Speaky` defaults domain (named after the process,
///   because Info.plist had no `CFBundleIdentifier`). They now live in the
///   bundle identifier's domain (`com.bedriyan.speaky`).
/// - History lived in SwiftData's generic `~/Library/Application Support/default.store`,
///   a file name any other non-sandboxed SwiftData app would also use. It now
///   lives in `~/Library/Application Support/Speaky/History.store`.
///
/// Both migrations **copy** and leave the old data where it was, so running an
/// older build afterwards still finds its settings and history.
enum LegacyStorageMigration {
    static let legacyDefaultsDomain = "Speaky"
    static let defaultsMarkerKey = "didMigrateLegacyDefaultsDomain"

    // MARK: - Settings

    /// Copy settings from the legacy domain into `defaults` once. Keys already
    /// present in `defaults` win. Returns the number of keys copied.
    @discardableResult
    static func migrateDefaults(legacy: [String: Any]?, into defaults: UserDefaults) -> Int {
        guard !defaults.bool(forKey: defaultsMarkerKey) else { return 0 }
        var copied = 0
        for (key, value) in legacy ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        defaults.set(true, forKey: defaultsMarkerKey)
        if copied > 0 {
            logger.info("Copied \(copied) settings from the legacy '\(legacyDefaultsDomain, privacy: .public)' domain")
        }
        return copied
    }

    /// Run the settings migration for the app's own defaults.
    static func migrateStandardDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        // Without a bundle identifier, .standard *is* the legacy domain.
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID != legacyDefaultsDomain else { return }
        migrateDefaults(legacy: defaults.persistentDomain(forName: legacyDefaultsDomain), into: defaults)
    }

    // MARK: - History store

    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// SwiftData's default store location, used by earlier versions.
    static var legacyHistoryStoreURL: URL {
        applicationSupport.appendingPathComponent("default.store")
    }

    static var historyStoreURL: URL {
        applicationSupport.appendingPathComponent("Speaky/History.store")
    }

    enum StoreMigrationResult: Equatable {
        case notNeeded      // new store already exists, or no legacy store
        case notSpeakys     // legacy store has no Speaky transcriptions table; left alone
        case copied
        case failed(String)
    }

    /// Copy the legacy history store to `newURL` if `newURL` doesn't exist yet
    /// and the legacy file really is Speaky's (has a `ZTRANSCRIPTION` table).
    /// Uses SQLite's online backup API, so WAL contents are included and the
    /// copy is consistent. The copy is written next to `newURL` and renamed
    /// into place, so a crash can never leave a half-written store behind.
    static func migrateHistoryStore(from legacyURL: URL, to newURL: URL) -> StoreMigrationResult {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newURL.path), fm.fileExists(atPath: legacyURL.path) else {
            return .notNeeded
        }

        var source: OpaquePointer?
        guard sqlite3_open_v2(legacyURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let source else {
            sqlite3_close(source)
            return .failed("cannot open legacy store")
        }
        defer { sqlite3_close(source) }

        guard hasTable(source, named: "ZTRANSCRIPTION") else { return .notSpeakys }

        do {
            try fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failed("cannot create directory: \(error.localizedDescription)")
        }

        let tempURL = newURL.deletingLastPathComponent()
            .appendingPathComponent(".\(newURL.lastPathComponent).migrating-\(UUID().uuidString)")
        defer {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                try? fm.removeItem(atPath: tempURL.path + suffix)
            }
        }

        var dest: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &dest, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let dest else {
            sqlite3_close(dest)
            return .failed("cannot create new store")
        }
        guard let backup = sqlite3_backup_init(dest, "main", source, "main") else {
            let message = String(cString: sqlite3_errmsg(dest))
            sqlite3_close(dest)
            return .failed("backup init: \(message)")
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        // Fold any WAL into the main file so a single rename moves everything.
        sqlite3_exec(dest, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_close(dest)
        guard stepResult == SQLITE_DONE else {
            return .failed("backup step: \(stepResult)")
        }

        do {
            try fm.moveItem(at: tempURL, to: newURL)
        } catch {
            return .failed("cannot move new store into place: \(error.localizedDescription)")
        }
        logger.info("Copied history from the legacy SwiftData default store")
        return .copied
    }

    private static func hasTable(_ db: OpaquePointer, named name: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
