import Foundation
import CoreAudio
import AudioToolbox
import os

private let logger = Logger.speaky(category: "AudioControlService")

/// Mutes system output while recording (`BackgroundAudioMode.muteSystemAudio`).
///
/// All bookkeeping lives in `SystemMuteController` (reference-counted, per-device,
/// crash-safe); this class wires it to the real CoreAudio hardware.
final class AudioControlService: @unchecked Sendable {
    private let controller: SystemMuteController

    init(
        hardware: OutputAudioHardware = CoreAudioOutputHardware(),
        store: MuteRestoreStore = UserDefaultsMuteRestoreStore()
    ) {
        controller = SystemMuteController(hardware: hardware, store: store)
    }

    func mute() { controller.mute() }
    func unmute() { controller.unmute() }
    func restoreAll() { controller.restoreAll() }
    func recoverFromPreviousSession() { controller.recoverFromPreviousSession() }

    // MARK: - Input Device Enumeration

    struct AudioDeviceInfo: Identifiable, Hashable {
        /// Runtime id. Not stable: it can change after a reboot or reconnect.
        let id: AudioDeviceID
        let name: String
        /// Persistent identifier; this is what settings store.
        var uid: String = ""
        var isBuiltIn = false
    }

    /// Find the built-in microphone by checking device transport type.
    /// Returns nil if no built-in input device is found (e.g. Mac Pro with no built-in mic).
    static func builtInInputDevice() -> AudioDeviceInfo? {
        inputDevices().first(where: \.isBuiltIn)
    }

    /// Persistent UID for a runtime device id, if that device is present.
    static func deviceUID(_ id: AudioDeviceID) -> String? {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func isBuiltIn(_ id: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transportType) == noErr
            && transportType == kAudioDeviceTransportTypeBuiltIn
    }

    static func inputDevices() -> [AudioDeviceInfo] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)

        return deviceIDs.compactMap { id -> AudioDeviceInfo? in
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var propSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &propSize)

            let bufferListPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(propSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { bufferListPtr.deallocate() }
            AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &propSize, bufferListPtr)

            let bufferList = bufferListPtr.assumingMemoryBound(to: AudioBufferList.self).pointee
            guard bufferList.mNumberBuffers > 0 else { return nil }

            // Get device name
            // The HAL returns a +1 retained CFString; take ownership so it's released.
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return AudioDeviceInfo(
                id: id,
                name: (name?.takeRetainedValue() as String?) ?? "",
                uid: deviceUID(id) ?? "",
                isBuiltIn: isBuiltIn(id)
            )
        }
    }
}

// MARK: - CoreAudio output hardware

final class CoreAudioOutputHardware: OutputAudioHardware, @unchecked Sendable {
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "speaky.default-output-listener")

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func defaultOutputDevice() -> UInt32? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.defaultOutputAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    func uid(of deviceID: UInt32) -> String? {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    func device(forUID uid: String) -> UInt32? {
        var deviceIDs: [AudioDeviceID] = []
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return nil
        }
        deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return nil
        }
        return deviceIDs.first { self.uid(of: $0) == uid }
    }

    func isMuted(_ deviceID: UInt32) -> Bool? {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.muteAddress
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        if status != noErr {
            logger.warning("Failed to get mute state for device \(deviceID): OSStatus \(status)")
            return nil
        }
        return muted != 0
    }

    @discardableResult
    func setMuted(_ deviceID: UInt32, _ muted: Bool) -> Bool {
        var val: UInt32 = muted ? 1 : 0
        var address = Self.muteAddress
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
        if status != noErr {
            logger.warning("Failed to set mute state for device \(deviceID): OSStatus \(status)")
            return false
        }
        return true
    }

    func startObservingDefaultOutput(_ handler: @escaping @Sendable () -> Void) {
        stopObservingDefaultOutput()
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block
        )
        if status == noErr {
            defaultOutputListener = block
        } else {
            logger.warning("Failed to observe default output device: OSStatus \(status)")
        }
    }

    func stopObservingDefaultOutput() {
        guard let block = defaultOutputListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block
        )
        defaultOutputListener = nil
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

/// Picks the microphone to record from.
enum InputDeviceSelection {
    /// - The selected device (matched by persistent UID) if it is connected.
    /// - Otherwise "Auto": the built-in mic, so Bluetooth headsets connecting
    ///   don't hijack the input.
    /// - nil means "use the system default input".
    static func resolve(
        selectedUID: String?,
        devices: [AudioControlService.AudioDeviceInfo]
    ) -> AudioControlService.AudioDeviceInfo? {
        if let selectedUID, !selectedUID.isEmpty,
           let device = devices.first(where: { $0.uid == selectedUID }) {
            return device
        }
        return devices.first(where: \.isBuiltIn)
    }
}
