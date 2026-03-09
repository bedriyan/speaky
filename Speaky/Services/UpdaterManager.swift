import Foundation
import Sparkle
import os

private let logger = Logger.speaky(category: "UpdaterManager")

private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if arch(arm64)
        return "https://bedriyan.github.io/speaky/appcast-arm64.xml"
        #else
        return "https://bedriyan.github.io/speaky/appcast-x86_64.xml"
        #endif
    }
}

@MainActor
final class UpdaterManager: ObservableObject {
    private let sparkleDelegate = SparkleDelegate()
    private let updater: SPUUpdater
    @Published var canCheckForUpdates = false

    private var observation: NSKeyValueObservation?

    init() {
        let userDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: sparkleDelegate
        )

        observation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func startIfEnabled(checkForUpdates: Bool) {
        updater.automaticallyChecksForUpdates = checkForUpdates
        do {
            try updater.start()
            logger.info("Sparkle updater started (autoCheck: \(checkForUpdates))")
        } catch {
            logger.error("Failed to start Sparkle updater: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        logger.info("Automatic update checks: \(enabled)")
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
