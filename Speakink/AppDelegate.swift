import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Prompt for accessibility if not already granted
        if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                PasteService.requestAccessibility()
            }
        }

        // Pre-warm the transcription engine at launch so first transcription is instant
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            appState?.warmUpEngine()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}
