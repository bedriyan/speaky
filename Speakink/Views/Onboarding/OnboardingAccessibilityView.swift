import SwiftUI
import AppKit

struct OnboardingAccessibilityView: View {
    let onContinue: () -> Void

    @State private var permissionGranted = false
    @State private var showContent = false
    @State private var checkTimer: Timer?
    @State private var alreadyGranted = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(permissionGranted ? Theme.success.opacity(0.15) : Theme.amber.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: permissionGranted ? "checkmark.circle.fill" : "accessibility")
                    .font(.system(size: 44))
                    .foregroundStyle(permissionGranted ? Theme.success : Theme.amber)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(spacing: 8) {
                Text("Accessibility Access")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(alreadyGranted
                     ? "Accessibility access is already enabled. You're good to go!"
                     : "Speakink needs Accessibility access to paste transcribed text at your cursor position.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if !permissionGranted {
                // Info box — only show when not yet granted
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.amber)

                    Text("When prompted, click \"Open System Settings\", find Speakink in the list, and enable the toggle.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(12)
                .background(Theme.amber.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 420)
            }

            Spacer().frame(height: 16)

            VStack(spacing: 12) {
                if permissionGranted {
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 220, height: 48)
                            .background(Theme.amberGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: requestAccessibility) {
                        Text("Enable Accessibility")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 220, height: 48)
                            .background(Theme.amberGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onContinue) {
                    Text("Skip for now")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 20)
        .onAppear {
            let trusted = AXIsProcessTrusted()
            if trusted {
                permissionGranted = true
                alreadyGranted = true
            }
            withAnimation(.easeOut(duration: 0.5)) { showContent = true }

            // Auto-advance after a short delay if already granted
            if trusted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    onContinue()
                }
            }
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    private func requestAccessibility() {
        PasteService.requestAccessibility()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let trusted = AXIsProcessTrusted()
            if trusted {
                checkTimer?.invalidate()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    permissionGranted = true
                }
            }
        }
    }
}
