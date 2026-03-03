import SwiftUI

struct NotchRecordingView: View {
    var appState: AppState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulseAnimation = false


    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Compact recording bar (always same size)
            if let appState {
                if appState.isTranscribing {
                    // Transcribing — just dots, no extra pulsing circle
                    HStack(spacing: 8) {
                        TranscribingDotsView()

                        Text("Transcribing")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                } else if appState.showingCancelWarning {
                    // Cancel warning
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)

                        Text("Press ESC again to cancel")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                } else {
                    // Recording controls — compact
                    HStack(spacing: 10) {
                        // Pulsing dot
                        ZStack {
                            Circle()
                                .fill(Theme.amber.opacity(0.25))
                                .frame(width: 16, height: 16)
                                .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                                .opacity(pulseAnimation ? 0.0 : 0.5)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: pulseAnimation)

                            Circle()
                                .fill(Theme.amberGradient)
                                .frame(width: 7, height: 7)
                        }

                        // Waveform
                        NotchWaveformView(levels: appState.audioLevels)
                            .frame(width: 80, height: 20)

                        // Timer
                        Text(formatTime(elapsedTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.amber.opacity(0.9))

                        // Stop button
                        Button {
                            appState.toggleRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.amber.opacity(0.15))
                                    .frame(width: 20, height: 20)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.amber)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }

        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !reduceMotion { pulseAnimation = true }
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    elapsedTime += 0.1
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

}

// MARK: - Notch Waveform

struct NotchWaveformView: View {
    let levels: [Float]

    private let barCount = 20
    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 2
    private let maxBarHeight: CGFloat = 18
    private let cornerRadius: CGFloat = 1.0

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let levelIndex = levels.isEmpty ? 0 : index * levels.count / barCount
                let level = levelIndex < levels.count ? CGFloat(levels[levelIndex]) : 0

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(barGradient(for: level))
                    .frame(width: barWidth, height: max(minBarHeight, level * maxBarHeight))
                    .animation(.easeOut(duration: 0.06), value: level)
            }
        }
    }

    private func barGradient(for level: CGFloat) -> some ShapeStyle {
        if level > 0.6 {
            return Theme.amber
        } else if level > 0.3 {
            return Theme.amber.opacity(0.7)
        } else {
            return Theme.amber.opacity(0.25 + Double(level) * 0.8)
        }
    }
}

// MARK: - Transcribing dots

struct TranscribingDotsView: View {
    @State private var dotIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.amber.opacity(index <= dotIndex ? 0.9 : 0.25))
                    .frame(width: 5, height: 5)
                    .scaleEffect(index == dotIndex ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: dotIndex)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in
                    dotIndex = (dotIndex + 1) % 3
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
