import CoreAudio
import Foundation
import os

private let logger = Logger.speaky(category: "PlaybackController")

/// Controls media playback (pause/resume) during recording sessions.
///
/// Sends pause and play through the private MediaRemote framework, but only
/// when something is actually playing. A "play" command sent while no media
/// app is active is routed by macOS to the Music app, which launches it, so
/// Speaky must never send "play" unless its "pause" really stopped something.
///
/// Since macOS 15.4, third-party apps can't read MediaRemote's now-playing
/// state, so playback is detected with public Core Audio instead: which other
/// processes are currently sending audio to an output device.
final class PlaybackController: @unchecked Sendable {
    typealias SendCommand = (UInt32) -> Void

    private let sendCommand: SendCommand?
    /// PIDs of other processes currently producing output audio.
    private let outputtingProcesses: () -> Set<pid_t>
    private let verifyDelay: TimeInterval
    private let queue: DispatchQueue

    private let lock = NSLock()
    /// Processes that were playing when we sent pause.
    private var pausedCandidates: Set<pid_t> = []
    /// Set once we've seen a candidate actually stop after our pause.
    private var didPause = false
    /// Bumped on every pause/resume so a late check from an old session is ignored.
    private var session = 0

    static let kMRPlay: UInt32 = 0
    static let kMRPause: UInt32 = 1

    init(
        sendCommand: SendCommand? = PlaybackController.mediaRemoteSendCommand(),
        outputtingProcesses: @escaping () -> Set<pid_t> = { AudioOutputActivity.otherProcessesPlaying() },
        verifyDelay: TimeInterval = 0.5,
        queue: DispatchQueue = DispatchQueue(label: "speaky.playback", qos: .userInitiated)
    ) {
        self.sendCommand = sendCommand
        self.outputtingProcesses = outputtingProcesses
        self.verifyDelay = verifyDelay
        self.queue = queue
    }

    /// Pause media if something is playing. Doesn't block the caller.
    func pause() {
        guard let sendCommand else { return }
        let playing = outputtingProcesses()
        lock.lock()
        session += 1
        let current = session
        didPause = false
        pausedCandidates = playing
        lock.unlock()

        guard !playing.isEmpty else {
            logger.debug("Nothing playing; no pause sent")
            return
        }
        sendCommand(Self.kMRPause)
        logger.debug("Media pause command sent")

        // Only something that stopped playing after our pause will be resumed.
        queue.asyncAfter(deadline: .now() + verifyDelay) { [weak self] in
            self?.confirmPause(session: current)
        }
    }

    /// Resume media only if our pause actually stopped something.
    func resume() {
        lock.lock()
        let pending = pausedCandidates
        lock.unlock()
        // If the recording was shorter than the check delay, check right now.
        let stoppedNow = !pending.isEmpty && !pending.subtracting(outputtingProcesses()).isEmpty

        lock.lock()
        session += 1
        let shouldResume = didPause || stoppedNow
        didPause = false
        pausedCandidates = []
        lock.unlock()

        guard shouldResume, let sendCommand else {
            logger.debug("Nothing was paused by Speaky; no play sent")
            return
        }
        sendCommand(Self.kMRPlay)
        logger.debug("Media resumed")
    }

    /// Wait for a pending pause check to finish. For tests.
    func waitForPendingChecks() {
        queue.sync {}
    }

    private func confirmPause(session expected: Int) {
        let stillPlaying = outputtingProcesses()
        lock.lock()
        defer { lock.unlock() }
        guard session == expected else { return }
        didPause = !pausedCandidates.subtracting(stillPlaying).isEmpty
        logger.debug("Pause confirmed: \(self.didPause)")
    }

    // MARK: - MediaRemote

    private typealias MRSendCommandFunc = @convention(c) (UInt32, AnyObject?) -> Bool

    static func mediaRemoteSendCommand() -> SendCommand? {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
        ), let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
            logger.warning("Failed to load MediaRemote framework")
            return nil
        }
        let function = unsafeBitCast(pointer, to: MRSendCommandFunc.self)
        return { command in _ = function(command, nil) }
    }
}

/// Which processes are producing sound, from Core Audio's per-process objects.
enum AudioOutputActivity {
    static func otherProcessesPlaying() -> Set<pid_t> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result = Set<pid_t>()
        for process in processObjects() where isRunningOutput(process) {
            if let pid = pid(of: process), pid != ownPID { result.insert(pid) }
        }
        return result
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr ? pid : nil
    }
}
