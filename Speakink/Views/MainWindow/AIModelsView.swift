import SwiftUI

struct AIModelsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAllModels = false
    @State private var showGroqAlert = false

    var body: some View {
        @Bindable var settings = appState.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Current model card
                DefaultModelCard()

                // Language picker
                HStack {
                    Text("Language")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    LanguagePicker(selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    ))
                    .frame(width: 180)
                }
                .padding(.horizontal)

                // Recommended section
                Text("Recommended")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal)

                LazyVStack(spacing: 12) {
                    ForEach(TranscriptionModels.recommended) { model in
                        #if arch(arm64)
                        if model.type == .parakeet {
                            PrimaryModelCard(model: model, onSelectBlocked: { showGroqAlert = true })
                        } else {
                            ModelCard(model: model, onSelectBlocked: { showGroqAlert = true })
                        }
                        #else
                        ModelCard(model: model, onSelectBlocked: { showGroqAlert = true })
                        #endif
                    }
                }
                .padding(.horizontal)

                // Import custom model
                importCustomModelButton
                    .padding(.horizontal)

                // Show all toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAllModels.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAllModels ? "chevron.up" : "chevron.down")
                            .font(.caption)
                        Text(showAllModels ? "Hide additional models" : "Show all available models")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Theme.amber)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)

                if showAllModels {
                    LazyVStack(spacing: 12) {
                        ForEach(TranscriptionModels.expanded) { model in
                            ModelCard(model: model, onSelectBlocked: { showGroqAlert = true })
                        }
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                #if !arch(arm64)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Some models require Apple Silicon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                #endif

                Spacer(minLength: 20)
            }
            .padding(.top, 16)
        }
        .navigationTitle("AI Models")
        .alert("Groq API Key Required", isPresented: $showGroqAlert) {
            Button("Open Settings") {
                // Post notification to switch to settings tab
                NotificationCenter.default.post(name: .switchToSettings, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add your Groq API key in Settings before selecting this model.")
        }
    }

    // MARK: - Import Custom Model

    private var importCustomModelButton: some View {
        Button {
            importCustomModel()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(Theme.amber)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Custom Model")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Load a custom GGML Whisper model from disk")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func importCustomModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let path = try? appState.modelManager.importCustomModel(from: url) {
                let model = TranscriptionModels.customWhisper(path: path)
                appState.settings.selectedModelID = model.id
            }
        }
    }
}

// MARK: - Notification for tab switching

extension Notification.Name {
    static let switchToSettings = Notification.Name("switchToSettings")
}

// MARK: - Default Model Card

struct DefaultModelCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let model = appState.settings.selectedModel

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Default Model")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            }

            Text(model.name)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    RatingDots(rating: model.speedRating, color: Theme.amber)
                }
                HStack(spacing: 4) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    RatingDots(rating: model.accuracyRating, color: Theme.success)
                }
            }
        }
        .padding()
        .background(Theme.amber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.amber.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Primary Model Card (larger, prominent for Parakeet)

struct PrimaryModelCard: View {
    @Environment(AppState.self) private var appState
    let model: TranscriptionModelInfo
    var onSelectBlocked: () -> Void

    private var isSelected: Bool { model.id == appState.settings.selectedModelID }
    private var isDownloaded: Bool { appState.modelManager.isDownloaded(model) }
    private var downloadProgress: Double? { appState.modelManager.downloadProgress[model.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.textPrimary)
                        Text("Best Pick")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.amber.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                if isSelected {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.success)
                }
            }

            Text(model.description)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    RatingDots(rating: model.speedRating, color: Theme.amber)
                }
                HStack(spacing: 4) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    RatingDots(rating: model.accuracyRating, color: Theme.success)
                }
                if let size = model.size {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            modelActions
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Theme.amber.opacity(0.08) : Theme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.amber.opacity(0.5), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var modelActions: some View {
        HStack(spacing: 12) {
            if isDownloaded {
                if !isSelected {
                    Button("Select as Default") {
                        appState.settings.selectedModelID = model.id
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                }
                Button("Delete", role: .destructive) {
                    if model.type == .parakeet {
                        appState.modelManager.deleteParakeetModel(model)
                    } else {
                        try? appState.modelManager.deleteModel(model)
                    }
                    if isSelected {
                        appState.settings.selectedModelID = TranscriptionModels.available.first?.id ?? ""
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.8))
            } else if let progress = downloadProgress, progress < 1.0 {
                ProgressView(value: progress)
                    .tint(Theme.amber)
                    .frame(maxWidth: 200)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Button("Download") {
                    Task {
                        if model.type == .parakeet {
                            _ = try? await appState.modelManager.downloadParakeetModel(model)
                        } else {
                            guard let url = model.downloadURL, let fileName = model.fileName else { return }
                            _ = try? await appState.modelManager.downloadModel(id: model.id, from: url, fileName: fileName)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.amber)
            }
        }
    }
}

// MARK: - Model Card

struct ModelCard: View {
    @Environment(AppState.self) private var appState
    let model: TranscriptionModelInfo
    var onSelectBlocked: (() -> Void)? = nil

    private var isSelected: Bool { model.id == appState.settings.selectedModelID }
    private var isDownloaded: Bool { appState.modelManager.isDownloaded(model) }
    private var downloadProgress: Double? { appState.modelManager.downloadProgress[model.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.success)
                }
            }

            Text(model.description)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    RatingDots(rating: model.speedRating, color: Theme.amber)
                }
                HStack(spacing: 4) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    RatingDots(rating: model.accuracyRating, color: Theme.success)
                }
                if let size = model.size {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(model.languageSupport)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 12) {
                if isDownloaded || model.type == .groq {
                    if !isSelected {
                        Button("Select as Default") {
                            selectModel()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.amber)
                    }

                    if isDownloaded && model.type != .groq {
                        Button("Delete", role: .destructive) {
                            if model.type == .parakeet {
                                appState.modelManager.deleteParakeetModel(model)
                            } else {
                                try? appState.modelManager.deleteModel(model)
                            }
                            if isSelected {
                                appState.settings.selectedModelID = TranscriptionModels.available.first?.id ?? ""
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red.opacity(0.8))
                    }
                } else if let progress = downloadProgress, progress < 1.0 {
                    ProgressView(value: progress)
                        .tint(Theme.amber)
                        .frame(maxWidth: 200)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Button("Download") {
                        Task {
                            if model.type == .parakeet {
                                _ = try? await appState.modelManager.downloadParakeetModel(model)
                            } else {
                                guard let url = model.downloadURL, let fileName = model.fileName else { return }
                                _ = try? await appState.modelManager.downloadModel(id: model.id, from: url, fileName: fileName)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Theme.amber.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.amber.opacity(0.3) : Theme.textTertiary.opacity(0.2), lineWidth: 1)
        )
    }

    private func selectModel() {
        // Groq requires API key validation
        if model.type == .groq {
            let hasKey = KeychainHelper.read(service: Constants.keychainService, account: "groq-api-key")
            if hasKey == nil || hasKey?.isEmpty == true {
                onSelectBlocked?()
                return
            }
        }
        appState.settings.selectedModelID = model.id
    }
}

// MARK: - Rating Dots

struct RatingDots: View {
    let rating: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= rating ? color : color.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
