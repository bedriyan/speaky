import SwiftUI

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButtons = false
    @State private var pulseWave = false
    @State private var currentTagline = 0
    @State private var taglineTimer: Timer?

    private let taglines = [
        "Voice to text, instantly.",
        "Speak freely, type nothing.",
        "Your words, transcribed.",
        "Private. Fast. Local."
    ]

    var body: some View {
        VStack(spacing: 28) {
            // Animated waveform icon
            ZStack {
                Circle()
                    .fill(Theme.amber.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseWave ? 1.15 : 1.0)
                    .opacity(pulseWave ? 0.4 : 0.8)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulseWave)

                Circle()
                    .fill(Theme.amber.opacity(0.18))
                    .frame(width: 88, height: 88)

                Image(systemName: "waveform")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Theme.amber)
            }

            VStack(spacing: 10) {
                Text("Welcome to")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(showTitle ? 1 : 0)

                Text("Speakink")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 12)

                Text(taglines[currentTagline])
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .opacity(showSubtitle ? 1 : 0)
                    .frame(height: 22)
            }

            Spacer().frame(height: 12)

            VStack(spacing: 14) {
                Button(action: onContinue) {
                    Text("Get Started")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 220, height: 48)
                        .background(Theme.amberGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("Skip Tour")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .opacity(showButtons ? 1 : 0)
            .offset(y: showButtons ? 0 : 12)
        }
        .onAppear {
            if reduceMotion {
                showTitle = true
                showSubtitle = true
                showButtons = true
            } else {
                pulseWave = true
                withAnimation(.easeOut(duration: 0.6).delay(0.2)) { showTitle = true }
                withAnimation(.easeOut(duration: 0.6).delay(0.5)) { showSubtitle = true }
                withAnimation(.easeOut(duration: 0.6).delay(0.8)) { showButtons = true }
            }

            taglineTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentTagline = (currentTagline + 1) % taglines.count
                    }
                }
            }
        }
        .onDisappear {
            taglineTimer?.invalidate()
            taglineTimer = nil
        }
    }
}
