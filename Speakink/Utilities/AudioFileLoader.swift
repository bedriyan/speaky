import Foundation
import AVFoundation

enum AudioFileLoader {
    /// Load audio from a file and convert to 16kHz mono Float32 samples.
    static func loadSamples(from url: URL, sampleRate: Double = AudioRecorder.sampleRate) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.invalidAudioFile
        }

        let sourceFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { throw TranscriptionError.invalidAudioFile }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TranscriptionError.invalidAudioFile
        }
        try audioFile.read(into: sourceBuffer)

        // Convert if needed
        let outputBuffer: AVAudioPCMBuffer
        if sourceFormat.sampleRate == targetFormat.sampleRate &&
           sourceFormat.channelCount == targetFormat.channelCount &&
           sourceFormat.commonFormat == targetFormat.commonFormat {
            outputBuffer = sourceBuffer
        } else {
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                throw TranscriptionError.invalidAudioFile
            }
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
                throw TranscriptionError.invalidAudioFile
            }
            var error: NSError?
            var inputConsumed = false
            converter.convert(to: converted, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return sourceBuffer
            }
            if let error { throw error }
            outputBuffer = converted
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw TranscriptionError.invalidAudioFile
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }
}
