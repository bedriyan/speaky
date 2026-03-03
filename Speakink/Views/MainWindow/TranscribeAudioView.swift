import SwiftUI
import UniformTypeIdentifiers

struct TranscribeAudioView: View {
    @Environment(AppState.self) private var appState
    @State private var droppedFileURL: URL?
    @State private var selectedModelID: String = ""
    @State private var selectedLanguage: String = "auto"
    @State private var isTranscribing = false
    @State private var resultText: String?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if droppedFileURL == nil {
                    // No file loaded — waveform drop zone
                    emptyDropZone
                        .padding(.horizontal)
                } else {
                    // File loaded — file info + options side by side
                    fileLoadedSection
                        .padding(.horizontal)
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Result
                if let result = resultText {
                    resultCard(result)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 16)
        }
        .navigationTitle("Transcribe Audio")
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear {
            if selectedModelID.isEmpty {
                selectedModelID = appState.settings.selectedModelID
            }
            selectedLanguage = appState.settings.language
        }
    }

    // MARK: - Empty Drop Zone (waveform bars, no dashed border)

    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            // Decorative waveform bars
            HStack(spacing: 4) {
                ForEach(0..<15, id: \.self) { i in
                    let heights: [CGFloat] = [20, 32, 48, 28, 56, 40, 64, 36, 52, 28, 44, 60, 24, 40, 32]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.amber.opacity(isDropTargeted ? 0.8 : 0.3))
                        .frame(width: 4, height: heights[i])
                }
            }
            .padding(.top, 24)

            Text("Drop an audio file here")
                .font(.title3.bold())
                .foregroundStyle(isDropTargeted ? Theme.amber : Theme.textPrimary)

            Button("Browse Files") {
                chooseFile()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.amber)

            Text("WAV, MP3, M4A, FLAC, OGG, AAC")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDropTargeted ? Theme.amber.opacity(0.06) : Theme.bgCard)
        )
    }

    // MARK: - File Loaded Section

    private var fileLoadedSection: some View {
        VStack(spacing: 16) {
            // File info card
            if let url = droppedFileURL {
                HStack(spacing: 12) {
                    // Waveform icon
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(Theme.amber)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let fileSize = fileSize(url) {
                            Text(fileSize)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        droppedFileURL = nil
                        resultText = nil
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.bgCard)
                )
            }

            // Options
            VStack(spacing: 12) {
                HStack {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("", selection: $selectedModelID) {
                        ForEach(TranscriptionModels.available) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .frame(width: 200)
                }

                HStack {
                    Text("Language")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    LanguagePicker(selection: $selectedLanguage)
                        .frame(width: 200)
                }

                Button {
                    transcribe()
                } label: {
                    HStack(spacing: 6) {
                        if isTranscribing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTranscribing ? "Transcribing..." : "Transcribe")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.amber)
                .disabled(isTranscribing)
            }
        }
    }

    // MARK: - Result Card

    private func resultCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Result")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.amber)
            }

            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.amber.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    // MARK: - Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Constants.supportedAudioExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            droppedFileURL = url
            resultText = nil
            errorMessage = nil
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let ext = url.pathExtension.lowercased()
            guard Constants.supportedAudioExtensions.contains(ext) else { return }
            Task { @MainActor in
                droppedFileURL = url
                resultText = nil
                errorMessage = nil
            }
        }
        return true
    }

    private func transcribe() {
        guard let fileURL = droppedFileURL else { return }
        isTranscribing = true
        errorMessage = nil
        resultText = nil

        Task {
            do {
                let text = try await appState.transcribeExternalAudio(
                    fileURL: fileURL,
                    modelID: selectedModelID,
                    language: selectedLanguage
                )
                resultText = text
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribing = false
        }
    }
}
