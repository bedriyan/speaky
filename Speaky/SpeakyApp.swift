import SwiftUI
import SwiftData

@main
struct SpeakyApp: App {
    @State private var appState: AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let modelContainer: ModelContainer

    init() {
        if Self.isRunningAsTestHost {
            // Unit tests launch the app as their host: never migrate or open
            // the user's real settings and history from a test run.
            modelContainer = try! ModelContainer(
                for: Transcription.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } else {
            // Must run before anything reads settings (AppSettings, KeyboardShortcuts).
            LegacyStorageMigration.migrateStandardDefaultsIfNeeded()
            Self.resetOnboardingIfFreshInstall()
            modelContainer = Self.makeModelContainer()
        }
        let appState = AppState()
        // Wire history saving up front. It used to be set only when the main
        // window appeared, so dictations made in a session where the window
        // was never opened were pasted but silently left out of history.
        appState.modelContext = modelContainer.mainContext
        _appState = State(initialValue: appState)
    }

    private static var isRunningAsTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// History lives in Speaky's own folder instead of SwiftData's generic
    /// `default.store`. Existing history is copied over on first launch.
    private static func makeModelContainer() -> ModelContainer {
        let legacyURL = LegacyStorageMigration.legacyHistoryStoreURL
        let storeURL = LegacyStorageMigration.historyStoreURL
        let result = LegacyStorageMigration.migrateHistoryStore(from: legacyURL, to: storeURL)
        if case .failed = result {
            // Keep using the old store rather than starting with empty history.
            if let container = try? ModelContainer(
                for: Transcription.self,
                configurations: ModelConfiguration(url: legacyURL)
            ) {
                return container
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            return try ModelContainer(for: Transcription.self, configurations: ModelConfiguration(url: storeURL))
        } catch {
            // Last resort: the previous default behaviour.
            return try! ModelContainer(for: Transcription.self)
        }
    }

    var body: some Scene {
        Window("Speaky", id: "main") {
            ContentRootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 440, height: 520)

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
    }

    /// If the sentinel file doesn't exist, this is a fresh install — reset onboarding.
    private static func resetOnboardingIfFreshInstall() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let speakyDir = appSupport.appendingPathComponent("Speaky")
        let sentinelFile = speakyDir.appendingPathComponent(".installed")

        if !FileManager.default.fileExists(atPath: sentinelFile.path) {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            try? FileManager.default.createDirectory(at: speakyDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: sentinelFile.path, contents: nil)
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
                // Check if permissions were revoked since last launch
                appState.checkPermissionsOnLaunch()
            }
            // Start Sparkle updater
            appState.updaterManager.startIfEnabled(checkForUpdates: appState.settings.checkForUpdates)
        }
    }
}
