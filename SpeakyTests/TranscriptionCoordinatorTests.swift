import Testing
import Foundation
@testable import Speaky

@Suite("TranscriptionCoordinator")
@MainActor
struct TranscriptionCoordinatorTests {

    private func makeCoordinator(
        audioRecorder: MockAudioRecorder = MockAudioRecorder(),
        pasteService: MockPasteService = MockPasteService(),
        audioControl: MockAudioControl = MockAudioControl(),
        modelManager: MockModelManager = MockModelManager(),
        deviceGuard: MockDeviceGuard = MockDeviceGuard(),
        soundEffect: MockSoundEffect = MockSoundEffect()
    ) -> (TranscriptionCoordinator, MockAudioRecorder, MockPasteService, MockAudioControl, MockDeviceGuard, MockSoundEffect) {
        let settings = AppSettings()
        let coordinator = TranscriptionCoordinator(
            settings: settings,
            audioRecorder: audioRecorder,
            pasteService: pasteService,
            audioControl: audioControl,
            modelManager: modelManager,
            deviceGuard: deviceGuard,
            soundEffect: soundEffect
        )
        return (coordinator, audioRecorder, pasteService, audioControl, deviceGuard, soundEffect)
    }

    @Test("startRecording calls audio recorder")
    func startRecordingCallsRecorder() throws {
        let recorder = MockAudioRecorder()
        let (coordinator, _, _, _, _, _) = makeCoordinator(audioRecorder: recorder)
        try coordinator.startRecording { _ in }
        #expect(recorder.startCalled)
    }

    @Test("startRecording locks device guard when device is selected")
    func startRecordingLocksDevice() throws {
        let guard_ = MockDeviceGuard()
        let settings = AppSettings()
        settings.selectedAudioDevice = 42
        let coordinator = TranscriptionCoordinator(
            settings: settings,
            audioRecorder: MockAudioRecorder(),
            pasteService: MockPasteService(),
            audioControl: MockAudioControl(),
            modelManager: MockModelManager(),
            deviceGuard: guard_,
            soundEffect: MockSoundEffect()
        )
        try coordinator.startRecording { _ in }
        #expect(guard_.lockedDeviceID == 42)
    }

    @Test("stopRecording unmutes audio and unlocks device")
    func stopRecordingUnmutesAndUnlocks() throws {
        let recorder = MockAudioRecorder()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.wav")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(count: 100))
        recorder.stopURL = tempURL
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let control = MockAudioControl()
        let guard_ = MockDeviceGuard()
        let (coordinator, _, _, _, _, _) = makeCoordinator(
            audioRecorder: recorder,
            audioControl: control,
            deviceGuard: guard_
        )

        _ = try coordinator.stopRecording()
        #expect(control.unmuteCount == 1)
        #expect(guard_.unlockCalled)
    }

    @Test("cancelRecording cleans up resources")
    func cancelRecordingCleansUp() throws {
        let recorder = MockAudioRecorder()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("cancel_test.wav")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(count: 100))
        recorder.stopURL = tempURL
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let control = MockAudioControl()
        let guard_ = MockDeviceGuard()
        let (coordinator, _, _, _, _, _) = makeCoordinator(
            audioRecorder: recorder,
            audioControl: control,
            deviceGuard: guard_
        )

        coordinator.cancelRecording()
        #expect(recorder.stopCalled)
        #expect(control.unmuteCount == 1)
        #expect(guard_.unlockCalled)
    }

    @Test("playStartSoundAndMute respects settings")
    func playStartSoundRespectsSettings() async {
        let sound = MockSoundEffect()
        let settings = AppSettings()
        settings.soundEffectsEnabled = true
        settings.muteSystemAudio = true

        let control = MockAudioControl()
        let coordinator = TranscriptionCoordinator(
            settings: settings,
            audioRecorder: MockAudioRecorder(),
            pasteService: MockPasteService(),
            audioControl: control,
            modelManager: MockModelManager(),
            deviceGuard: MockDeviceGuard(),
            soundEffect: sound
        )

        await coordinator.playStartSoundAndMute()
        #expect(sound.playStartCalled)
        #expect(control.muteCount == 1)
    }

    @Test("playStartSoundAndMute skips when disabled")
    func playStartSoundSkipsWhenDisabled() async {
        let sound = MockSoundEffect()
        let settings = AppSettings()
        settings.soundEffectsEnabled = false
        settings.muteSystemAudio = false

        let control = MockAudioControl()
        let coordinator = TranscriptionCoordinator(
            settings: settings,
            audioRecorder: MockAudioRecorder(),
            pasteService: MockPasteService(),
            audioControl: control,
            modelManager: MockModelManager(),
            deviceGuard: MockDeviceGuard(),
            soundEffect: sound
        )

        await coordinator.playStartSoundAndMute()
        #expect(!sound.playStartCalled)
        #expect(control.muteCount == 0)
    }
}
