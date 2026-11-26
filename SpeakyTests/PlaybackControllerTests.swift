import Foundation
import Testing
@testable import Speaky

/// Records commands and lets each test script what is playing.
private final class FakeMedia: @unchecked Sendable {
    private let lock = NSLock()
    private var _playing: Set<pid_t>
    private var _sent: [UInt32] = []
    /// What the player does when it receives pause.
    var stopsOnPause = true

    init(playing: Set<pid_t>) { _playing = playing }

    var playing: Set<pid_t> {
        get { lock.lock(); defer { lock.unlock() }; return _playing }
        set { lock.lock(); _playing = newValue; lock.unlock() }
    }
    var sent: [UInt32] { lock.lock(); defer { lock.unlock() }; return _sent }

    func send(_ command: UInt32) {
        lock.lock()
        _sent.append(command)
        if command == PlaybackController.kMRPause, stopsOnPause { _playing = [] }
        lock.unlock()
    }

    func controller() -> PlaybackController {
        PlaybackController(
            sendCommand: { [self] in send($0) },
            outputtingProcesses: { [self] in playing },
            verifyDelay: 0
        )
    }
}

@Suite("PlaybackController")
struct PlaybackControllerTests {
    @Test("nothing playing: no pause and, crucially, no play (which launches Music)")
    func nothingPlaying() {
        let media = FakeMedia(playing: [])
        let controller = media.controller()
        controller.pause()
        controller.waitForPendingChecks()
        controller.resume()
        #expect(media.sent.isEmpty)
    }

    @Test("music playing: paused, then resumed")
    func pausesAndResumes() {
        let media = FakeMedia(playing: [42])
        let controller = media.controller()
        controller.pause()
        controller.waitForPendingChecks()
        controller.resume()
        #expect(media.sent == [PlaybackController.kMRPause, PlaybackController.kMRPlay])
    }

    @Test("sound that pause doesn't stop (a call): no play afterwards")
    func callKeepsPlaying() {
        let media = FakeMedia(playing: [7])
        media.stopsOnPause = false
        let controller = media.controller()
        controller.pause()
        controller.waitForPendingChecks()
        controller.resume()
        #expect(media.sent == [PlaybackController.kMRPause])
    }

    @Test("resume twice only plays once")
    func resumeOnce() {
        let media = FakeMedia(playing: [42])
        let controller = media.controller()
        controller.pause()
        controller.waitForPendingChecks()
        controller.resume()
        controller.resume()
        #expect(media.sent.filter { $0 == PlaybackController.kMRPlay }.count == 1)
    }

    @Test("a very short recording still resumes the music")
    func quickStop() {
        let media = FakeMedia(playing: [42])
        let controller = PlaybackController(
            sendCommand: { media.send($0) },
            outputtingProcesses: { media.playing },
            verifyDelay: 5
        )
        controller.pause()
        controller.resume()
        #expect(media.sent == [PlaybackController.kMRPause, PlaybackController.kMRPlay])
    }

    @Test("a check from an earlier recording can't arm a later resume")
    func staleCheckIgnored() {
        let media = FakeMedia(playing: [42])
        let controller = PlaybackController(
            sendCommand: { media.send($0) },
            outputtingProcesses: { media.playing },
            verifyDelay: 0.2
        )
        controller.pause()
        controller.resume()            // quick stop: resumes
        media.playing = []             // user then stops the music
        controller.pause()             // next recording: nothing playing
        Thread.sleep(forTimeInterval: 0.3)
        controller.waitForPendingChecks()
        controller.resume()
        #expect(media.sent == [PlaybackController.kMRPause, PlaybackController.kMRPlay])
    }
}
