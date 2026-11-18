import Testing
import Foundation
@testable import Speaky

/// A start sound that keeps "playing" until the test releases it.
@MainActor
final class GatedSoundEffect: SoundEffecting {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isPlaying = false

    func playStartAndWait() async {
        isPlaying = true
        await withCheckedContinuation { continuation = $0 }
        isPlaying = false
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }

    func playEnd() {}
}

@Suite("Background audio is always restored")
@MainActor
struct BackgroundAudioRaceTests {
    private func make(
        mode: BackgroundAudioMode,
        sound: any SoundEffecting = MockSoundEffect()
    ) -> (TranscriptionCoordinator, MockAudioRecorder, MockAudioControl, MockPlaybackController) {
        let settings = AppSettings()
        settings.backgroundAudioMode = mode
        settings.soundEffectsEnabled = true
        let recorder = MockAudioRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("race_\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: url.path, contents: Data(count: 10))
        recorder.stopURL = url
        let control = MockAudioControl()
        let playback = MockPlaybackController()
        let coordinator = TranscriptionCoordinator(
            settings: settings,
            audioRecorder: recorder,
            pasteService: MockPasteService(),
            audioControl: control,
            modelManager: MockModelManager(),
            deviceGuard: MockDeviceGuard(),
            soundEffect: sound,
            playbackController: playback
        )
        return (coordinator, recorder, control, playback)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    @Test("stop during the start sound does not mute afterwards")
    func stopDuringStartSound() async throws {
        let sound = GatedSoundEffect()
        let (c, _, control, _) = make(mode: .muteSystemAudio, sound: sound)
        try c.startRecording { _ in }
        let muteTask = Task { await c.playStartSoundAndMute() }
        await waitUntil { sound.isPlaying }
        _ = try c.stopRecording()         // user stops while the sound plays
        sound.finish()
        await muteTask.value
        #expect(control.muteCount == 0)
        #expect(control.outstandingHolds == 0)
    }

    @Test("cancel during the start sound does not mute afterwards")
    func cancelDuringStartSound() async throws {
        let sound = GatedSoundEffect()
        let (c, _, control, _) = make(mode: .muteSystemAudio, sound: sound)
        try c.startRecording { _ in }
        let muteTask = Task { await c.playStartSoundAndMute() }
        await waitUntil { sound.isPlaying }
        c.cancelRecording()
        sound.finish()
        await muteTask.value
        #expect(control.outstandingHolds == 0)
    }

    @Test("a late start sound from an old recording cannot mute a new one twice")
    func staleSessionIgnored() async throws {
        let sound = GatedSoundEffect()
        let (c, _, control, _) = make(mode: .muteSystemAudio, sound: sound)
        try c.startRecording { _ in }
        let first = Task { await c.playStartSoundAndMute() }
        await waitUntil { sound.isPlaying }
        _ = try c.stopRecording()
        sound.finish()
        await first.value
        try c.startRecording { _ in }      // new recording
        let second = Task { await c.playStartSoundAndMute() }
        await waitUntil { sound.isPlaying }
        sound.finish()
        await second.value
        #expect(control.muteCount == 1)
        _ = try c.stopRecording()
        #expect(control.outstandingHolds == 0)
    }

    @Test("normal dictation mutes once and restores once")
    func normalCycle() async throws {
        let (c, _, control, _) = make(mode: .muteSystemAudio)
        try c.startRecording { _ in }
        await c.playStartSoundAndMute()
        #expect(control.outstandingHolds == 1)
        _ = try c.stopRecording()
        #expect(control.outstandingHolds == 0)
    }

    @Test("changing the setting mid-recording still restores the mute")
    func modeChangedMidRecording() async throws {
        let (c, _, control, _) = make(mode: .muteSystemAudio)
        try c.startRecording { _ in }
        await c.playStartSoundAndMute()
        c.settingsForTesting.backgroundAudioMode = .off
        _ = try c.stopRecording()
        #expect(control.outstandingHolds == 0)
    }

    @Test("a failing stop still restores the mute")
    func stopErrorRestores() async throws {
        let (c, recorder, control, _) = make(mode: .muteSystemAudio)
        try c.startRecording { _ in }
        await c.playStartSoundAndMute()
        recorder.stopURL = nil             // stop() will throw
        #expect(throws: (any Error).self) { try c.stopRecording() }
        #expect(control.outstandingHolds == 0)
    }

    @Test("a failing start resumes paused media")
    func startErrorResumesMedia() throws {
        let (c, recorder, _, playback) = make(mode: .pauseMedia)
        recorder.startError = AudioRecorderError.noOutputURL
        #expect(throws: (any Error).self) { try c.startRecording { _ in } }
        #expect(playback.pauseCount == 1)
        #expect(playback.resumeCount == 1)
    }

    @Test("termination restores everything")
    func terminationRestores() async throws {
        let (c, _, control, _) = make(mode: .muteSystemAudio)
        try c.startRecording { _ in }
        await c.playStartSoundAndMute()
        c.restoreBackgroundAudioForTermination()
        #expect(control.outstandingHolds == 0)
        #expect(control.restoreAllCount == 1)
    }
}
