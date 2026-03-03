import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case microphone
    case accessibility
    case modelDownload
    case complete
}

struct OnboardingContainerView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentStep: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            OnboardingBackgroundView()

            VStack(spacing: 0) {
                if currentStep != .welcome && currentStep != .complete {
                    OnboardingProgressView(
                        currentStep: currentStep.rawValue - 1,
                        totalSteps: 3
                    )
                    .padding(.top, 32)
                }

                Spacer()

                Group {
                    switch currentStep {
                    case .welcome:
                        OnboardingWelcomeView {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentStep = .microphone
                            }
                        } onSkip: {
                            hasCompletedOnboarding = true
                        }
                    case .microphone:
                        OnboardingMicrophoneView {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentStep = .accessibility
                            }
                        }
                    case .accessibility:
                        OnboardingAccessibilityView {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentStep = .modelDownload
                            }
                        }
                    case .modelDownload:
                        OnboardingModelDownloadView {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentStep = .complete
                            }
                        }
                    case .complete:
                        OnboardingCompleteView {
                            hasCompletedOnboarding = true
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()
            }
        }
        .frame(minWidth: 600, minHeight: 480)
    }
}

// MARK: - Background

struct OnboardingBackgroundView: View {
    var body: some View {
        ZStack {
            Theme.bgDark

            // Warm amber radial glow
            RadialGradient(
                gradient: Gradient(colors: [
                    Theme.amber.opacity(0.12),
                    Theme.amber.opacity(0.04),
                    Color.clear
                ]),
                center: .top,
                startRadius: 30,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Progress Dots

struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Theme.amber : Color.white.opacity(0.2))
                    .frame(width: index == currentStep ? 24 : 8, height: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
            }
        }
    }
}
