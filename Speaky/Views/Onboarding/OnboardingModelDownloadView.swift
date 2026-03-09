import SwiftUI

struct OnboardingModelDownloadView: View {
    @Environment(AppState.self) private var appState
    let onContinue: () -> Void

    @State private var isDownloading = false
    @State private var isDownloaded = false
    @State private var downloadError: String?
    @State private var showContent = false
    @State private var showGroqSetup = false
    @State private var groqKeyInput: String = ""
    @State private var groqSaveError: String?
    @State private var pulseOffset: CGFloat = 0

    private let recommendedModel: TranscriptionModelInfo = {
        #if arch(arm64)
        return TranscriptionModels.available.first { $0.id == "parakeet-v3" }
            ?? TranscriptionModels.available[0]
        #else
        return TranscriptionModels.available.first { $0.id == "whisper-small-q5_1" }
            ?? TranscriptionModels.available[0]
        #endif
    }()

    var body: some View {
        VStack(spacing: 24) {
            SpeakyAnimationView(animation: isDownloaded ? .celebration : .listening)
                .frame(width: 160, height: 160)

            VStack(spacing: 8) {
                Text("Downloading AI Model")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Setting up \(recommendedModel.name) for fast, private transcription.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // Model info card
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendedModel.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        HStack(spacing: 8) {
                            Label(recommendedModel.size ?? "", systemImage: "arrow.down.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)

                            Label("Local & Private", systemImage: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.success.opacity(0.8))
                        }
                    }

                    Spacer()

                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.success)
                    }
                }

                if isDownloading {
                    let progress = appState.modelManager.downloadProgress[recommendedModel.id] ?? 0
                    let phase = appState.modelManager.parakeetDownloadPhase

                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))

                                if phase == .warmingUp {
                                    // Indeterminate pulsing bar for warm-up phase
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Theme.amberGradient)
                                        .frame(width: geo.size.width * 0.3)
                                        .offset(x: pulseOffset * (geo.size.width * 0.7))
                                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseOffset)
                                        .onAppear { pulseOffset = 1.0 }
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Theme.amberGradient)
                                        .frame(width: geo.size.width * max(progress, 0.02))
                                        .animation(.easeOut(duration: 0.5), value: progress)
                                }
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text(phaseLabel(phase))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if phase != .warmingUp {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.amber)
                            }
                        }
                    }
                }

                if let error = downloadError {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.recording)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Retry") {
                            startDownload()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .buttonStyle(.handCursor)
                    }
                }
            }
            .padding(16)
            .background(Theme.amber.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber.opacity(0.15), lineWidth: 1))
            .frame(maxWidth: 400)

            Spacer().frame(height: 8)

            if isDownloaded {
                Button(action: {
                    appState.settings.selectedModelID = recommendedModel.id
                    onContinue()
                }) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 220, height: 48)
                        .background(Theme.amberGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.handCursor)
            } else if isDownloading {
                let phase = appState.modelManager.parakeetDownloadPhase
                Text(phase == .warmingUp ? "Almost ready..." : "This may take a minute...")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }

            if !isDownloaded {
                Button(action: onContinue) {
                    Text("Skip for now")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.handCursor)
            }

            // Cloud transcription alternative
            if !isDownloaded {
                Button {
                    showGroqSetup = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11))
                        Text("Or use cloud transcription instead")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.handCursor)
            }
        }
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 20)
        .sheet(isPresented: $showGroqSetup) {
            groqSetupSheet
        }
        .onAppear {
            isDownloaded = appState.modelManager.isDownloaded(recommendedModel)
            withAnimation(.easeOut(duration: 0.5)) { showContent = true }

            // Auto-start download if not yet downloaded
            if !isDownloaded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !isDownloaded && !isDownloading {
                        startDownload()
                    }
                }
            }
        }
    }

    private var groqSetupSheet: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.amber)

                Text("Cloud Transcription")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Use Groq's cloud API for fast transcription without downloading a model.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            // How to get a key
            VStack(alignment: .leading, spacing: 10) {
                Text("How to get a free API key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Go to console.groq.com and create an account", systemImage: "1.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Label("Navigate to API Keys and create a new key", systemImage: "2.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Label("Copy the key and paste it below", systemImage: "3.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }

                Button {
                    if let url = URL(string: "https://console.groq.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("Open console.groq.com")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.amber)
                }
                .buttonStyle(.handCursor)
                .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // API key input
            VStack(spacing: 8) {
                SecureField("gsk_...", text: $groqKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                if let error = groqSaveError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.recording)
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    showGroqSetup = false
                    groqKeyInput = ""
                    groqSaveError = nil
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 100, height: 40)
                }
                .buttonStyle(.handCursor)

                Button {
                    guard !groqKeyInput.trimmingCharacters(in: .whitespaces).isEmpty else {
                        groqSaveError = "Please enter an API key."
                        return
                    }
                    KeychainHelper.save(service: Constants.keychainService, account: Constants.groqAPIKeyAccount, value: groqKeyInput.trimmingCharacters(in: .whitespaces))
                    appState.settings.selectedModelID = "groq-whisper"
                    showGroqSetup = false
                    groqKeyInput = ""
                    groqSaveError = nil
                    onContinue()
                } label: {
                    Text("Save & Continue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 160, height: 40)
                        .background(Theme.amberGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.handCursor)
            }

            Text("Free tier includes ~2 hours of audio per day — no credit card required.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 440)
        .background(Theme.bgDark)
    }

    private func startDownload() {
        isDownloading = true
        downloadError = nil
        pulseOffset = 0

        Task {
            do {
                if recommendedModel.type == .parakeet {
                    _ = try await appState.modelManager.downloadParakeetModel(recommendedModel)

                    // Phase 3: Warm up the engine (dummy inference to prime ANE)
                    appState.modelManager.parakeetDownloadPhase = .warmingUp
                    appState.coordinator.warmUpEngine()
                    // Give warm-up a moment to run
                    try? await Task.sleep(for: .seconds(2))
                    appState.modelManager.parakeetDownloadPhase = .idle
                } else {
                    guard let url = recommendedModel.downloadURL, let fileName = recommendedModel.fileName else { return }
                    _ = try await appState.modelManager.downloadModel(
                        id: recommendedModel.id,
                        from: url,
                        fileName: fileName
                    )
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isDownloaded = true
                    isDownloading = false
                }
            } catch {
                isDownloading = false
                downloadError = error.localizedDescription
            }
        }
    }

    private func phaseLabel(_ phase: ParakeetDownloadPhase) -> String {
        switch phase {
        case .idle: "Downloading..."
        case .downloading: "Downloading & preparing..."
        case .compiling: "Compiling model..."
        case .warmingUp: "Warming up..."
        }
    }
}
