import SwiftUI
@preconcurrency import KeyboardShortcuts

struct HotkeySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Custom Shortcut") {
                KeyboardShortcuts.Recorder("Shortcut:", name: .toggleRecording)

                Text("Click the recorder and press your desired key combination.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Modifier Key Presets") {
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
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkey")
    }
}
