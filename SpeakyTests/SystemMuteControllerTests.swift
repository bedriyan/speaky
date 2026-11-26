import Testing
import Foundation
@testable import Speaky

/// In-memory output devices with mute controls.
final class FakeOutputHardware: OutputAudioHardware, @unchecked Sendable {
    struct Device { var uid: String; var muted: Bool?; var connected = true }

    var devices: [UInt32: Device] = [:]
    var defaultOutput: UInt32?
    var setMutedCalls: [(UInt32, Bool)] = []
    var failSetMuted = false
    private(set) var observer: (@Sendable () -> Void)?

    func defaultOutputDevice() -> UInt32? { defaultOutput }
    func uid(of deviceID: UInt32) -> String? { devices[deviceID]?.uid }
    func device(forUID uid: String) -> UInt32? {
        devices.first { $0.value.uid == uid && $0.value.connected }?.key
    }
    func isMuted(_ deviceID: UInt32) -> Bool? { devices[deviceID]?.muted }
    func setMuted(_ deviceID: UInt32, _ muted: Bool) -> Bool {
        setMutedCalls.append((deviceID, muted))
        guard !failSetMuted, devices[deviceID]?.muted != nil else { return false }
        devices[deviceID]?.muted = muted
        return true
    }
    func startObservingDefaultOutput(_ handler: @escaping @Sendable () -> Void) { observer = handler }
    func stopObservingDefaultOutput() { observer = nil }

    /// Simulate the system switching the default output device.
    func switchDefaultOutput(to id: UInt32) {
        defaultOutput = id
        observer?()
    }
}

final class InMemoryMuteStore: MuteRestoreStore {
    var uids: [String] = []
    func load() -> [String] { uids }
    func save(_ uids: [String]) { self.uids = uids }
}

@Suite("SystemMuteController")
struct SystemMuteControllerTests {
    private func make(
        speakersMuted: Bool = false
    ) -> (SystemMuteController, FakeOutputHardware, InMemoryMuteStore) {
        let hw = FakeOutputHardware()
        hw.devices = [
            1: .init(uid: "speakers", muted: speakersMuted),
            2: .init(uid: "airpods", muted: false),
        ]
        hw.defaultOutput = 1
        let store = InMemoryMuteStore()
        return (SystemMuteController(hardware: hw, store: store), hw, store)
    }

    @Test("mute then unmute restores the original unmuted state")
    func basicRoundTrip() {
        let (c, hw, store) = make()
        c.mute()
        #expect(hw.devices[1]?.muted == true)
        #expect(store.uids == ["speakers"])
        c.unmute()
        #expect(hw.devices[1]?.muted == false)
        #expect(store.uids.isEmpty)
    }

    @Test("a device the user had already muted stays muted")
    func keepsUserMute() {
        let (c, hw, store) = make(speakersMuted: true)
        c.mute()
        #expect(store.uids.isEmpty)
        c.unmute()
        #expect(hw.devices[1]?.muted == true)
        #expect(hw.setMutedCalls.isEmpty)
    }

    @Test("unmute without a matching mute does nothing")
    func unbalancedUnmuteIsNoOp() {
        let (c, hw, _) = make()
        c.unmute()
        c.unmute()
        #expect(hw.setMutedCalls.isEmpty)
        c.mute()
        #expect(hw.devices[1]?.muted == true)
        #expect(c.activeHolds == 1)
    }

    @Test("overlapping holds are reference counted")
    func referenceCounted() {
        let (c, hw, _) = make()
        c.mute()
        c.mute()
        #expect(hw.setMutedCalls.count == 1)
        c.unmute()
        #expect(hw.devices[1]?.muted == true)
        c.unmute()
        #expect(hw.devices[1]?.muted == false)
    }

    @Test("a second mute never re-reads the already muted state as the original")
    func secondMuteDoesNotOverwriteOriginal() {
        // The old implementation stored `wasMuted = getMuteState()` on every
        // mute(), so a second mute recorded `true` and unmute() skipped the unmute.
        let (c, hw, _) = make()
        c.mute()
        c.unmute()
        c.mute()
        c.mute()
        c.unmute()
        c.unmute()
        #expect(hw.devices[1]?.muted == false)
    }

    @Test("switching output mid-recording restores the original device, and the new one")
    func deviceChangeRestoresBoth() {
        let (c, hw, store) = make()
        c.mute()
        hw.switchDefaultOutput(to: 2)
        #expect(hw.devices[2]?.muted == true)
        #expect(store.uids == ["speakers", "airpods"])
        c.unmute()
        #expect(hw.devices[1]?.muted == false)
        #expect(hw.devices[2]?.muted == false)
        #expect(hw.observer == nil)
    }

    @Test("a disconnected device is skipped without failing the rest")
    func disconnectedDeviceSkipped() {
        let (c, hw, store) = make()
        c.mute()
        hw.switchDefaultOutput(to: 2)
        hw.devices[1]?.connected = false
        c.unmute()
        #expect(hw.devices[2]?.muted == false)
        #expect(store.uids.isEmpty)
    }

    @Test("restoreAll drops every hold and restores")
    func restoreAll() {
        let (c, hw, _) = make()
        c.mute()
        c.mute()
        c.restoreAll()
        #expect(hw.devices[1]?.muted == false)
        #expect(c.activeHolds == 0)
        c.unmute()
        #expect(hw.devices[1]?.muted == false)
    }

    @Test("startup recovery unmutes devices left muted by a crashed session")
    func crashRecovery() {
        let (c, hw, store) = make(speakersMuted: true)
        store.uids = ["speakers"]
        c.recoverFromPreviousSession()
        #expect(hw.devices[1]?.muted == false)
        #expect(store.uids.isEmpty)
    }

    @Test("startup recovery does nothing after a clean session")
    func noRecoveryNeeded() {
        let (c, hw, _) = make(speakersMuted: true)
        c.recoverFromPreviousSession()
        #expect(hw.devices[1]?.muted == true)
        #expect(hw.setMutedCalls.isEmpty)
    }

    @Test("a failed mute is not recorded, so nothing is wrongly restored")
    func failedMuteNotRecorded() {
        let (c, hw, store) = make()
        hw.failSetMuted = true
        c.mute()
        #expect(store.uids.isEmpty)
        hw.failSetMuted = false
        c.unmute()
        #expect(hw.setMutedCalls.count == 1)
    }
}
