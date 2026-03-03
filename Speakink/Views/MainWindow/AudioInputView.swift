import SwiftUI

struct AudioInputView: View {
    @Environment(AppState.self) private var appState
    @State private var inputDevices: [AudioControlService.AudioDeviceInfo] = []

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Input Device") {
                Picker("Input Device", selection: Binding(
                    get: { settings.selectedAudioDevice },
                    set: { settings.selectedAudioDevice = $0 }
                )) {
                    Text("System Default").tag(nil as UInt32?)
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id as UInt32?)
                    }
                }
            }

            Section("Recording Options") {
                Toggle("Mute system audio while recording", isOn: Binding(
                    get: { settings.muteSystemAudio },
                    set: { settings.muteSystemAudio = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Audio Input")
        .onAppear {
            inputDevices = AudioControlService.inputDevices()
        }
    }
}
