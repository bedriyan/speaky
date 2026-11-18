import Foundation
import os

private let logger = Logger.speaky(category: "SystemMuteController")

/// Low-level access to output devices, abstracted so the mute bookkeeping
/// can be unit tested without touching real hardware.
protocol OutputAudioHardware: AnyObject {
    /// The current default output device, or nil if none.
    func defaultOutputDevice() -> UInt32?
    /// A persistent identifier for a device (survives reconnects and reboots).
    func uid(of deviceID: UInt32) -> String?
    /// Resolve a persistent identifier back to a device that is present now.
    func device(forUID uid: String) -> UInt32?
    /// The device's mute state, or nil if it can't be read (no mute control).
    func isMuted(_ deviceID: UInt32) -> Bool?
    /// Set the device's mute state. Returns true on success.
    @discardableResult func setMuted(_ deviceID: UInt32, _ muted: Bool) -> Bool
    /// Call `handler` whenever the default output device changes, until stopped.
    func startObservingDefaultOutput(_ handler: @escaping @Sendable () -> Void)
    func stopObservingDefaultOutput()
}

/// Persists which devices Speaky muted, so a crash or force-quit while muted
/// can be undone on the next launch.
protocol MuteRestoreStore: AnyObject {
    func load() -> [String]
    func save(_ uids: [String])
}

final class UserDefaultsMuteRestoreStore: MuteRestoreStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pendingMuteRestoreDeviceUIDs") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String] { defaults.stringArray(forKey: key) ?? [] }

    func save(_ uids: [String]) {
        if uids.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(uids, forKey: key)
        }
    }
}

/// Reference-counted, per-device system output mute.
///
/// - `mute()` / `unmute()` must be balanced; extra `unmute()` calls are no-ops.
/// - Only devices that were *unmuted* when Speaky muted them are restored, so a
///   device the user had muted themselves stays muted.
/// - Restoration targets the device that was muted (by UID), not whatever the
///   default output happens to be at the time, so switching outputs mid-recording
///   (e.g. AirPods connecting) can't strand the original device muted.
/// - If the default output changes while muted, the new device is muted too and
///   restored together with the original one.
/// - The set of devices to restore is persisted, so `recoverFromPreviousSession()`
///   can undo a mute left behind by a crash.
/// - Volume is never changed.
final class SystemMuteController: @unchecked Sendable {
    private let hardware: OutputAudioHardware
    private let store: MuteRestoreStore
    private let lock = NSLock()

    private var holdCount = 0
    /// UIDs of devices Speaky switched from unmuted to muted, in mute order.
    private var mutedByUs: [String] = []

    init(hardware: OutputAudioHardware, store: MuteRestoreStore) {
        self.hardware = hardware
        self.store = store
    }

    /// Number of outstanding `mute()` calls (for diagnostics and tests).
    var activeHolds: Int { lock.withLock { holdCount } }

    func mute() {
        lock.withLock {
            holdCount += 1
            guard holdCount == 1 else { return }
            muteDefaultOutputLocked()
            hardware.startObservingDefaultOutput { [weak self] in
                self?.defaultOutputDidChange()
            }
        }
    }

    func unmute() {
        lock.withLock {
            guard holdCount > 0 else { return }
            holdCount -= 1
            guard holdCount == 0 else { return }
            restoreLocked()
        }
    }

    /// Drop every hold and restore all devices Speaky muted.
    /// Used on app termination and other "must not leave audio muted" paths.
    func restoreAll() {
        lock.withLock {
            holdCount = 0
            restoreLocked()
        }
    }

    /// Undo a mute left behind by a previous run that ended while muted.
    func recoverFromPreviousSession() {
        lock.withLock {
            guard holdCount == 0 else { return }
            let pending = store.load()
            guard !pending.isEmpty else { return }
            logger.warning("Restoring \(pending.count) output device(s) left muted by a previous session")
            mutedByUs = pending
            restoreLocked()
        }
    }

    /// Called when the default output device changes while muted.
    func defaultOutputDidChange() {
        lock.withLock {
            guard holdCount > 0 else { return }
            muteDefaultOutputLocked()
        }
    }

    // MARK: - Private (lock held)

    private func muteDefaultOutputLocked() {
        guard let deviceID = hardware.defaultOutputDevice(),
              let uid = hardware.uid(of: deviceID) else {
            logger.warning("No default output device to mute")
            return
        }
        guard !mutedByUs.contains(uid) else { return }
        guard hardware.isMuted(deviceID) == false else {
            // Already muted by the user (or unreadable): leave it alone and
            // don't record it, so we never unmute something we didn't mute.
            return
        }
        guard hardware.setMuted(deviceID, true) else { return }
        mutedByUs.append(uid)
        store.save(mutedByUs)
        logger.info("Muted output device \(deviceID)")
    }

    private func restoreLocked() {
        hardware.stopObservingDefaultOutput()
        for uid in mutedByUs {
            guard let deviceID = hardware.device(forUID: uid) else {
                logger.info("Muted device is no longer connected; nothing to restore")
                continue
            }
            if hardware.setMuted(deviceID, false) {
                logger.info("Restored output device \(deviceID)")
            }
        }
        mutedByUs.removeAll()
        store.save([])
    }
}
