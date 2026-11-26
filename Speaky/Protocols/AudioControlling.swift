import Foundation

/// Abstraction over system audio mute/unmute for testability.
///
/// `mute()` and `unmute()` are reference counted: every `mute()` must be
/// balanced by one `unmute()`, and an `unmute()` without a matching `mute()`
/// does nothing.
protocol AudioControlling: AnyObject {
    func mute()
    func unmute()
    /// Drop all holds and restore every device that was muted by Speaky.
    func restoreAll()
    /// Undo a mute left behind by a previous run (crash, force quit).
    func recoverFromPreviousSession()
}

extension AudioControlService: AudioControlling {}
