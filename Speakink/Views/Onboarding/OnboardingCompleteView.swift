import SwiftUI

struct OnboardingCompleteView: View {
    let onFinish: () -> Void

    @State private var showContent = false
    @State private var showCheckmark = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Theme.success.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(showCheckmark ? 1.0 : 0.5)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.success)
                    .scaleEffect(showCheckmark ? 1.0 : 0.0)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showCheckmark)

            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Speakink is ready to go. Use the global hotkey to start recording, or click the menu bar icon.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Quick tips
            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "option", text: "Press Option+R to start/stop recording")
                tipRow(icon: "doc.on.clipboard", text: "Transcribed text is automatically pasted at your cursor")
                tipRow(icon: "gearshape", text: "Change models, hotkey, and more in Settings")
            }
            .padding(16)
            .background(Theme.amber.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: 380)

            Spacer().frame(height: 16)

            Button(action: onFinish) {
                Text("Start Using Speakink")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 240, height: 48)
                    .background(Theme.amberGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .opacity(showContent ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { showContent = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) { showCheckmark = true }
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.amber)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
