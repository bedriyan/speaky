import SwiftUI
import SwiftData

@main
struct SpeakyApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Speaky", id: "main") {
            ContentRootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .modelContainer(for: Transcription.self)
        .defaultSize(width: 440, height: 520)

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
    }
}

struct ContentRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainWindowView()
            } else {
                OnboardingContainerView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .onAppear {
            // Wire SwiftData context into AppState for saving transcriptions
            appState.modelContext = modelContext
            // Run auto-cleanup on launch
            CleanupService.performCleanup(
                context: modelContext,
                interval: appState.settings.cleanupIntervalEnum
            )
            // Pre-warm the selected engine to avoid cold start delay
            if hasCompletedOnboarding {
                appState.warmUpEngine()
            }
        }
    }
}
