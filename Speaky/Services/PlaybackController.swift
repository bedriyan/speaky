import Foundation
import os

private let logger = Logger.speaky(category: "PlaybackController")

/// Controls media playback (pause/resume) during recording sessions.
/// Uses the private MediaRemote framework for precise pause/play commands.
/// Only resumes if something was actually playing when we paused.
final class PlaybackController: @unchecked Sendable {
    private typealias MRSendCommandFunc = @convention(c) (UInt32, AnyObject?) -> Bool

    private let sendCommand: MRSendCommandFunc?
    private var didPause = false

    private static let kMRPlay: UInt32 = 0
    private static let kMRPause: UInt32 = 1

    init() {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
        ) else {
            logger.warning("Failed to load MediaRemote framework")
            sendCommand = nil
            return
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(ptr, to: MRSendCommandFunc.self)
        } else {
            sendCommand = nil
        }
    }

    /// Pause currently playing media immediately without blocking the caller.
    ///
    /// Sends the MediaRemote pause command unconditionally. The previous
    /// implementation used a `DispatchSemaphore` to check NowPlaying info first,
    /// which blocked the main thread for up to 100ms and — on timeout — skipped
    /// the pause entirely, causing the multi-second delay users experienced.
    func pause() {
        guard let sendCommand else { return }
        _ = sendCommand(Self.kMRPause, nil)
        didPause = true
        logger.debug("Media pause command sent")
    }

    /// Resume media only if we actually paused something.
    func resume() {
        guard didPause, let sendCommand else { return }
        _ = sendCommand(Self.kMRPlay, nil)
        didPause = false
        logger.debug("Media resumed")
    }
}
