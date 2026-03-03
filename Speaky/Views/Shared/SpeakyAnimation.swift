import Foundation

enum SpeakyAnimation: String, Equatable {
    case neutral = "neutral"
    case listening = "listening"
    case listeningShort = "listening-short"
    case longListening = "long-listening"
    case transcribing = "transcribing"
    case celebration = "celebration"
    case error = "error"
    case sleeping = "sleeping"

    var filename: String { rawValue }

    var isOneShot: Bool {
        switch self {
        case .celebration, .error: true
        default: false
        }
    }

    var oneShotFollowUp: SpeakyAnimation {
        .neutral
    }
}

extension RecordingState {
    var speakyAnimation: SpeakyAnimation {
        switch self {
        case .idle: .neutral
        case .recording: .listening
        case .transcribing: .transcribing
        case .error: .error
        }
    }
}
