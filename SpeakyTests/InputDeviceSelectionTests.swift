import Testing
import Foundation
@testable import Speaky

@Suite("Input device selection")
struct InputDeviceSelectionTests {
    let builtIn = AudioControlService.AudioDeviceInfo(id: 79, name: "MacBook Pro Microphone", uid: "BuiltInMicrophoneDevice", isBuiltIn: true)
    let iphone = AudioControlService.AudioDeviceInfo(id: 84, name: "iPhone Microphone", uid: "iphone-uid")

    @Test("the selected mic is found by UID even when its runtime id changed")
    func selectedByUID() {
        let reconnected = AudioControlService.AudioDeviceInfo(id: 131, name: "iPhone Microphone", uid: "iphone-uid")
        #expect(InputDeviceSelection.resolve(selectedUID: "iphone-uid", devices: [builtIn, reconnected])?.id == 131)
    }

    @Test("a disconnected selected mic falls back to the built-in mic")
    func disconnectedFallsBack() {
        #expect(InputDeviceSelection.resolve(selectedUID: "iphone-uid", devices: [builtIn])?.id == 79)
    }

    @Test("Auto uses the built-in mic")
    func autoUsesBuiltIn() {
        #expect(InputDeviceSelection.resolve(selectedUID: nil, devices: [iphone, builtIn])?.id == 79)
    }

    @Test("no built-in mic and nothing selected: system default")
    func noBuiltIn() {
        #expect(InputDeviceSelection.resolve(selectedUID: nil, devices: [iphone]) == nil)
    }

    @Test("a saved legacy device id is converted to a UID while the device is present")
    func legacyIDMigrated() {
        let defaults = UserDefaults.isolatedForTesting()
        defaults.set(UInt32(84), forKey: "selectedAudioDevice")
        let settings = AppSettings(defaults: defaults, uidForLegacyDeviceID: { $0 == 84 ? "iphone-uid" : nil })
        #expect(settings.selectedAudioDeviceUID == "iphone-uid")
        #expect(defaults.string(forKey: "selectedAudioDeviceUID") == "iphone-uid")
        #expect(defaults.object(forKey: "selectedAudioDevice") == nil)
        // Relaunch keeps it.
        #expect(AppSettings(defaults: defaults, uidForLegacyDeviceID: { _ in nil }).selectedAudioDeviceUID == "iphone-uid")
    }

    @Test("a stale legacy device id becomes Auto instead of pointing at the wrong mic")
    func staleLegacyIDDropped() {
        let defaults = UserDefaults.isolatedForTesting()
        defaults.set(UInt32(115), forKey: "selectedAudioDevice")
        let settings = AppSettings(defaults: defaults, uidForLegacyDeviceID: { _ in nil })
        #expect(settings.selectedAudioDeviceUID == nil)
        #expect(defaults.object(forKey: "selectedAudioDevice") == nil)
    }
}
