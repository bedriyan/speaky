import SwiftUI
import AVFoundation

struct OnboardingMicrophoneView: View {
    let onContinue: () -> Void

    @State private var permissionGranted = false
    @State private var permissionDenied = false
    @State private var showContent = false
    @State private var alreadyGranted = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(permissionGranted ? Theme.success.opacity(0.15) : Theme.amber.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: permissionGranted ? "checkmark.circle.fill" : "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(permissionGranted ? Theme.success : Theme.amber)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(spacing: 8) {
                Text("Microphone Access")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(alreadyGranted
                     ? "Microphone access is already enabled. You're good to go!"
                     : "Speakink needs access to your microphone to record speech for transcription.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            if permissionDenied {
                VStack(spacing: 8) {
                    Text("Microphone access was denied.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.amber)

                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.amber)
                    .font(.system(size: 14, weight: .medium))
                }
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
                    Button(action: requestMicPermission) {
                        Text("Enable Microphone")
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
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .authorized {
                permissionGranted = true
                alreadyGranted = true
            } else if status == .denied || status == .restricted {
                permissionDenied = true
            }
            withAnimation(.easeOut(duration: 0.5)) { showContent = true }

            // Auto-advance after a short delay if already granted
            if status == .authorized {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    onContinue()
                }
            }
        }
    }

    private func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    permissionGranted = granted
                    permissionDenied = !granted
                }
            }
        }
    }
}
