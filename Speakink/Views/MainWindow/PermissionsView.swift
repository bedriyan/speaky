import SwiftUI

struct PermissionsView: View {
    @State private var accessibilityGranted = false
    @State private var pollTimer: Timer?

    var body: some View {
        Form {
            Section("Accessibility") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Access")
                            .font(.body)
                        Text("Required for auto-paste after transcription.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    } else {
                        Button("Grant Access") {
                            PasteService.requestAccessibility()
                        }
                        .foregroundStyle(Theme.amber)
                    }
                }

                if !accessibilityGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("If paste doesn't work after granting access:")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textSecondary)
                        Text("1. Open System Settings → Privacy & Security → Accessibility")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Text("2. Remove all \"Speakink\" entries using the − button")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Text("3. Click + and add Speakink from /Applications")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, 4)
                }

                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .foregroundStyle(Theme.amber)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onAppear {
            accessibilityGranted = PasteService.checkAccessibility()
            // Poll for changes while view is visible
            pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.permissionPollInterval, repeats: true) { _ in
                Task { @MainActor in
                    let current = PasteService.checkAccessibility()
                    if current != accessibilityGranted {
                        accessibilityGranted = current
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
