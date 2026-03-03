import Foundation

final class AudioLevelMonitor: @unchecked Sendable {
    private let onLevels: @Sendable ([Float]) -> Void
    private var levels: [Float]
    private let barCount: Int

    init(barCount: Int = 30, onLevels: @escaping @Sendable ([Float]) -> Void) {
        self.barCount = barCount
        self.levels = Array(repeating: 0, count: barCount)
        self.onLevels = onLevels
    }

    func process(samples: [Float]) {
        // Calculate RMS
        guard !samples.isEmpty else { return }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Convert to dB and normalize to 0…1
        let db = 20 * log10(max(rms, 1e-10))
        let normalized = max(0, min(1, (db + 60) / 60)) // -60dB → 0, 0dB → 1

        // Shift levels left and add new value
        levels.removeFirst()
        levels.append(normalized)

        onLevels(levels)
    }
}
