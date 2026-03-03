import Foundation
import SwiftData

@Model
final class Transcription {
    var id: UUID
    var text: String
    var date: Date
    var duration: TimeInterval
    var modelID: String
    var language: String
    var audioFileURL: String?

    init(text: String, duration: TimeInterval, modelID: String, language: String, audioFileURL: String? = nil) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.duration = duration
        self.modelID = modelID
        self.language = language
        self.audioFileURL = audioFileURL
    }
}
