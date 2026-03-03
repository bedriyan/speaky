import SwiftUI
@preconcurrency import KeyboardShortcuts

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var inputDevices: [AudioControlService.AudioDeviceInfo] = []
    @State private var accessibilityGranted = false
    @State private var pollTimer: Timer?
    @State private var groqAPIKey: String = ""

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            // Language
            Section("Language") {
                LanguagePicker(selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                ))
            }

            // Behavior
            Section("Behavior") {
                Toggle("Auto-paste after transcription", isOn: Binding(
                    get: { settings.autoPaste },
                    set: { settings.autoPaste = $0 }
                ))

                Toggle("Clean up transcriptions (remove filler words)", isOn: Binding(
                    get: { settings.cleanUpTranscriptions },
                    set: { settings.cleanUpTranscriptions = $0 }
                ))

                Toggle("Apply word replacements", isOn: Binding(
                    get: { settings.applyWordReplacements },
                    set: { settings.applyWordReplacements = $0 }
                ))
            }

            // Storage
            Section("Storage") {
                Picker("Auto-delete older than", selection: Binding(
                    get: { settings.cleanupIntervalEnum },
                    set: { settings.cleanupInterval = $0.rawValue }
                )) {
                    ForEach(CleanupInterval.allCases, id: \.self) { interval in
                        Text(interval.rawValue).tag(interval)
                    }
                }

                Text("Audio files and transcription records older than this will be automatically deleted. Usage statistics are preserved.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            // Hotkey
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Custom Shortcut:", name: .toggleRecording)

                Text("Or select a modifier key preset:")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                ForEach(HotkeyManager.HotkeyOption.allCases.filter(\.isModifierKey), id: \.id) { option in
                    Button {
                        appState.hotkeyManager.selectedHotkey = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if appState.hotkeyManager.selectedHotkey == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.amber)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text("Modifier keys support push-to-talk (hold) and hands-free (tap) modes.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            // Audio Input
            Section("Audio Input") {
                Picker("Input Device", selection: Binding(
                    get: { settings.selectedAudioDevice },
                    set: { settings.selectedAudioDevice = $0 }
                )) {
                    Text("System Default").tag(nil as UInt32?)
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id as UInt32?)
                    }
                }

                Toggle("Mute system audio while recording", isOn: Binding(
                    get: { settings.muteSystemAudio },
                    set: { settings.muteSystemAudio = $0 }
                ))
            }

            // Permissions
            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Access")
                            .font(.body)
                        Text("Required for auto-paste after transcription.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    } else {
                        Button("Grant Access") {
                            PasteService.requestAccessibility()
                        }
                        .foregroundStyle(Theme.amber)
                    }
                }

                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .foregroundStyle(Theme.amber)
            }

            // API Keys
            Section("API Keys") {
                HStack {
                    Text("Groq API Key")
                        .font(.body)
                    Spacer()
                    SecureField("sk-...", text: $groqAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onChange(of: groqAPIKey) { _, newValue in
                            if newValue.isEmpty {
                                KeychainHelper.delete(service: Constants.keychainService, account: "groq-api-key")
                            } else {
                                KeychainHelper.save(service: Constants.keychainService, account: "groq-api-key", value: newValue)
                            }
                        }
                }

                Text("Free API key from [groq.com](https://console.groq.com). Required for Groq Whisper cloud transcription.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            // General
            Section("General") {
                Button("Reset Onboarding") {
                    hasCompletedOnboarding = false
                }
                .foregroundStyle(Theme.amber)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            inputDevices = AudioControlService.inputDevices()
            accessibilityGranted = PasteService.checkAccessibility()
            groqAPIKey = KeychainHelper.read(service: Constants.keychainService, account: "groq-api-key") ?? ""
            pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.permissionPollInterval, repeats: true) { _ in
                Task { @MainActor in
                    let current = PasteService.checkAccessibility()
                    if current != accessibilityGranted {
                        accessibilityGranted = current
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
