import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Record button
            Button {
                appState.toggleRecording()
            } label: {
                Label(recordButtonTitle, systemImage: recordButtonIcon)
            }
            .keyboardShortcut("r")
            .disabled(appState.isTranscribing)

            // Error display with dismiss
            if case .error(let msg) = appState.state {
                Divider()
                Button {
                    appState.cancelTranscription()
                } label: {
                    Label(msg, systemImage: "exclamationmark.triangle")
                }
            }

            Divider()

            // Last transcription preview
            if let last = appState.lastTranscription {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(last, forType: .string)
                } label: {
                    Text(last.prefix(80) + (last.count > 80 ? "..." : ""))
                        .lineLimit(2)
                }

                Divider()
            }

            // Model picker - only show downloaded models
            Menu("Model: \(appState.settings.selectedModel.name)") {
                let downloadedModels = TranscriptionModels.available.filter { model in
                    appState.modelManager.isDownloaded(model)
                }
                ForEach(downloadedModels) { model in
                    Button {
                        appState.settings.selectedModelID = model.id
                    } label: {
                        HStack {
                            Text(model.name)
                            if model.id == appState.settings.selectedModelID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Open Speakink...") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Speakink") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var recordButtonTitle: String {
        switch appState.state {
        case .idle: "Start Recording"
        case .recording: "Stop Recording"
        case .transcribing: "Transcribing..."
        case .error: "Start Recording"
        }
    }

    private var recordButtonIcon: String {
        switch appState.state {
        case .idle: "mic.fill"
        case .recording: "stop.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .error: "mic.fill"
        }
    }
}
