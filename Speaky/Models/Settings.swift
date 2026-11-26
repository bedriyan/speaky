import Foundation
import os

private let settingsLogger = Logger.speaky(category: "Settings")

/// Controls when the transcription engine is unloaded from memory after idle.
enum EngineUnloadOption: String, CaseIterable {
    case never
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour

    var label: String {
        switch self {
        case .never: "Never"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        }
    }

    var description: String {
        switch self {
        case .never: "Model stays in memory for instant transcriptions"
        case .fiveMinutes: "Free memory after 5 minutes of inactivity"
        case .fifteenMinutes: "Free memory after 15 minutes of inactivity"
        case .thirtyMinutes: "Free memory after 30 minutes of inactivity"
        case .oneHour: "Free memory after 1 hour of inactivity"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .never: 0
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        }
    }

    init(from seconds: TimeInterval) {
        switch seconds {
        case 300: self = .fiveMinutes
        case 900: self = .fifteenMinutes
        case 1800: self = .thirtyMinutes
        case 3600: self = .oneHour
        default: self = .never
        }
    }
}

/// Controls how background audio is handled during recording.
enum BackgroundAudioMode: String, CaseIterable {
    case off
    case pauseMedia
    case muteSystemAudio

    var label: String {
        switch self {
        case .off: "Off"
        case .pauseMedia: "Pause media"
        case .muteSystemAudio: "Mute system audio"
        }
    }

    var description: String {
        switch self {
        case .off: "Background audio continues during recording"
        case .pauseMedia: "Pauses media players (Spotify, YouTube, etc.)"
        case .muteSystemAudio: "Mutes all system audio without pausing media"
        }
    }
}

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: "selectedModelID") }
    }
    var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }
    var backgroundAudioMode: BackgroundAudioMode {
        didSet { defaults.set(backgroundAudioMode.rawValue, forKey: "backgroundAudioMode") }
    }
    /// Persistent UID of the chosen microphone; nil means Auto (built-in mic).
    /// Device ids (`AudioDeviceID`) were stored before, but they change across
    /// reboots and reconnects, so the saved choice could point at nothing or at
    /// a different microphone.
    var selectedAudioDeviceUID: String? {
        didSet {
            if let uid = selectedAudioDeviceUID {
                defaults.set(uid, forKey: "selectedAudioDeviceUID")
            } else {
                defaults.removeObject(forKey: "selectedAudioDeviceUID")
            }
        }
    }
    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: "autoPaste") }
    }
    /// Apply what voice training learned (corrections and word hints) to dictation.
    var useVoiceTraining: Bool {
        didSet { defaults.set(useVoiceTraining, forKey: "useVoiceTraining") }
    }

    var cleanUpTranscriptions: Bool {
        didSet { defaults.set(cleanUpTranscriptions, forKey: "cleanUpTranscriptions") }
    }
    var autoUnloadTimeout: TimeInterval {
        didSet { defaults.set(autoUnloadTimeout, forKey: "autoUnloadTimeout") }
    }
    var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }
    var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") }
    }
    var cleanupInterval: String {
        didSet { defaults.set(cleanupInterval, forKey: "cleanupInterval") }
    }
    var cleanupIntervalEnum: CleanupInterval {
        CleanupInterval(rawValue: cleanupInterval) ?? .never
    }
    var engineUnloadOption: EngineUnloadOption {
        get { EngineUnloadOption(from: autoUnloadTimeout) }
        set { autoUnloadTimeout = newValue.seconds }
    }
    var selectedModel: TranscriptionModelInfo {
        TranscriptionModels.find(selectedModelID) ?? TranscriptionModels.available[0]
    }

    init(
        defaults: UserDefaults = .standard,
        uidForLegacyDeviceID: (UInt32) -> String? = { AudioControlService.deviceUID($0) }
    ) {
        self.defaults = defaults
        // Architecture-aware default model
        let defaultModel: String = {
            #if arch(arm64)
            return "parakeet-v3"
            #else
            return "whisper-small-q5_1"
            #endif
        }()

        // Migrate away from removed models (cloud engines, low-quality, incompatible mel bins)
        let savedModel = defaults.string(forKey: "selectedModelID") ?? defaultModel
        let removedModelIDs: Set<String> = [
            "deepgram-nova-3",
            "whisper-large-v3-turbo", "whisper-large-v3"
        ]

        #if !arch(arm64)
        // Intel: Parakeet requires Apple Neural Engine, migrate to Whisper
        let intelIncompatible: Set<String> = ["parakeet-v3"]
        let allRemoved = removedModelIDs.union(intelIncompatible)
        #else
        let allRemoved = removedModelIDs
        #endif

        if allRemoved.contains(savedModel) {
            self.selectedModelID = defaultModel
            defaults.set(defaultModel, forKey: "selectedModelID")
        } else {
            self.selectedModelID = savedModel
        }
        self.language = defaults.string(forKey: "language") ?? "auto"
        if let savedMode = defaults.string(forKey: "backgroundAudioMode"),
           let mode = BackgroundAudioMode(rawValue: savedMode) {
            self.backgroundAudioMode = mode
        } else {
            self.backgroundAudioMode = .pauseMedia
        }
        self.autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        self.cleanUpTranscriptions = defaults.object(forKey: "cleanUpTranscriptions") as? Bool ?? true
        self.useVoiceTraining = defaults.object(forKey: "useVoiceTraining") as? Bool ?? true
        // Default: 0 (never unload) — keeps model in memory for instant transcriptions.
        // Migrate users on the old 300s default to "never" since it caused cold-start issues.
        // This migration runs once; afterwards "5 minutes" is a valid user choice
        // (it used to be reset to "never" on every launch).
        let savedTimeout = defaults.object(forKey: "autoUnloadTimeout") as? TimeInterval
        let migratedKey = "didMigrateLegacyAutoUnloadDefault"
        if savedTimeout == nil || (savedTimeout == 300 && !defaults.bool(forKey: migratedKey)) {
            self.autoUnloadTimeout = 0
        } else {
            self.autoUnloadTimeout = savedTimeout!
        }
        defaults.set(true, forKey: migratedKey)
        self.soundEffectsEnabled = defaults.object(forKey: "soundEffectsEnabled") as? Bool ?? true
        self.checkForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
        self.cleanupInterval = defaults.string(forKey: "cleanupInterval") ?? "Never"
        if let uid = defaults.string(forKey: "selectedAudioDeviceUID") {
            self.selectedAudioDeviceUID = uid
        } else if let legacyID = defaults.object(forKey: "selectedAudioDevice") as? UInt32 {
            // Convert the old runtime id while that device is still the same one.
            // If it's gone, there's no way to know which mic it was: fall back to Auto.
            let uid = uidForLegacyDeviceID(legacyID)
            self.selectedAudioDeviceUID = uid
            if let uid { defaults.set(uid, forKey: "selectedAudioDeviceUID") }
        } else {
            self.selectedAudioDeviceUID = nil
        }
        defaults.removeObject(forKey: "selectedAudioDevice")
    }
}
