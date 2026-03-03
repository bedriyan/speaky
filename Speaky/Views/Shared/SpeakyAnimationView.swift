import SwiftUI
import AppKit

struct SpeakyAnimationView: NSViewRepresentable {
    let animation: SpeakyAnimation
    var onOneShotComplete: (@MainActor () -> Void)?

    func makeNSView(context: Context) -> SpeakyImageView {
        let view = SpeakyImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.isEditable = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        loadAnimation(into: view, animation: animation)
        return view
    }

    func updateNSView(_ nsView: SpeakyImageView, context: Context) {
        guard nsView.currentAnimation != animation else { return }
        loadAnimation(into: nsView, animation: animation)
    }

    private func loadAnimation(into view: SpeakyImageView, animation: SpeakyAnimation) {
        view.currentAnimation = animation
        view.onOneShotComplete = onOneShotComplete
        view.completionTask?.cancel()

        guard let url = Bundle.main.url(
            forResource: animation.filename,
            withExtension: "png",
            subdirectory: "Speaky"
        ) else { return }

        let image = NSImage(contentsOf: url)
        view.image = image
        view.animates = true

        if animation.isOneShot {
            view.scheduleOneShotCompletion()
        }
    }
}

@MainActor
final class SpeakyImageView: NSImageView {
    var currentAnimation: SpeakyAnimation?
    var onOneShotComplete: (@MainActor () -> Void)?
    var completionTask: Task<Void, Never>?

    func scheduleOneShotCompletion() {
        completionTask?.cancel()

        guard let image = self.image,
              let rep = image.representations.first as? NSBitmapImageRep else {
            // Fallback: fire after a fixed duration if metadata unavailable
            completionTask = Task {
                try? await Task.sleep(for: .seconds(4.0))
                guard !Task.isCancelled else { return }
                onOneShotComplete?()
            }
            return
        }

        let frameCount = (rep.value(forProperty: .frameCount) as? Int) ?? 1
        let frameDuration = (rep.value(forProperty: .currentFrameDuration) as? Double) ?? (1.0 / 24.0)
        let totalDuration = Double(frameCount) * frameDuration

        completionTask = Task {
            try? await Task.sleep(for: .seconds(totalDuration))
            guard !Task.isCancelled else { return }
            onOneShotComplete?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            completionTask?.cancel()
        }
    }

    deinit {
        completionTask?.cancel()
    }
}
